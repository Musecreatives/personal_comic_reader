import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../sync/sync_client.dart';
import 'debug_log.dart';

/// Reports are stored on the sync server as `tickets` records, so they need
/// no server changes; the developer reads and answers them on the server
/// (tickets.py next to the sync service's database).
const ticketsResource = 'tickets';

enum ReportKind { problem, crash, idea }

class ReportReply {
  final String from;
  final String text;
  final DateTime at;
  const ReportReply(this.from, this.text, this.at);
}

class ProblemReport {
  final String id;
  final ReportKind kind;
  final String title;
  final String details;

  /// open, in_progress, fixed, closed - set by the developer.
  final String status;
  final DateTime createdAt;
  final List<ReportReply> replies;

  const ProblemReport({
    required this.id,
    required this.kind,
    required this.title,
    required this.details,
    required this.status,
    required this.createdAt,
    required this.replies,
  });

  factory ProblemReport.fromRecord(SyncRecord r) {
    final d = r.data;
    return ProblemReport(
      id: r.recordId,
      kind: ReportKind.values.asNameMap()[d['type']] ?? ReportKind.problem,
      title: d['title'] as String? ?? '',
      details: d['details'] as String? ?? '',
      status: d['status'] as String? ?? 'open',
      createdAt: DateTime.tryParse(d['created_at'] as String? ?? '') ?? DateTime(2000),
      replies: [
        for (final e in (d['replies'] as List? ?? const []))
          ReportReply(
            e['from'] as String? ?? '',
            e['text'] as String? ?? '',
            DateTime.tryParse(e['at'] as String? ?? '') ?? DateTime(2000),
          ),
      ],
    );
  }
}

/// The ticket body, with the last stretch of logs and network calls when
/// [includeDiagnostics].
Map<String, dynamic> buildReport({
  required ReportKind kind,
  required String title,
  required String details,
  String? route,
  String? error,
  bool includeDiagnostics = true,
  DebugLog? log,
}) {
  final l = log ?? DebugLog.instance;
  List<T> last<T>(Iterable<T> all, int n) {
    final list = all.toList();
    return list.sublist(list.length > n ? list.length - n : 0);
  }

  return {
    'type': kind.name,
    'title': title,
    'details': details,
    'status': 'open',
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
    'route': ?route,
    'error': ?error,
    'replies': const [],
    if (includeDiagnostics) ...{
      'logs': [for (final e in last(l.logs, 150)) e.toJson()],
      'network': [for (final e in last(l.network, 80)) e.toJson()],
    },
  };
}

Future<void> sendReport(SyncClient client, Map<String, dynamic> report) async {
  await client.push(ticketsResource, [
    SyncRecord(
      recordId: const Uuid().v4(),
      data: report,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    ),
  ]);
}

/// Your reports, newest first, with the developer's replies.
Future<List<ProblemReport>> listReports(SyncClient client) async {
  final records = await client.pull(ticketsResource);
  return records.map(ProblemReport.fromRecord).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}
