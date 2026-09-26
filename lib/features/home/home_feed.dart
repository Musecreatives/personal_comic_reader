import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
import '../../core/history/history_entry.dart';

/// A series plus the server it lives on - ids are only unique per server
/// (Suwayomi's are small integers), so everything on the merged Home carries
/// its backend and is keyed by [key].
class FeedSeries {
  final Series series;
  final ReaderBackend backend;
  const FeedSeries(this.series, this.backend);

  String get serverId => backend.config.id;
  String get key => seriesKey(serverId, series.id);
}

/// Chapters added recently to one series, collapsed into a single row:
/// twelve new chapters of the same title are one line, not twelve.
class FeedRecent {
  final ReaderBackend backend;
  final String seriesId;
  final String seriesTitle;
  final String? thumbnailUrl;

  /// The newest chapter in the group.
  final Book latest;

  /// How many new chapters the group holds.
  final int count;

  const FeedRecent({
    required this.backend,
    required this.seriesId,
    required this.seriesTitle,
    required this.thumbnailUrl,
    required this.latest,
    required this.count,
  });
}

class HomeFeed {
  final List<FeedSeries> inProgress;
  final List<FeedRecent> recent;

  /// Servers that failed to answer - shown as a note, never as a blank page.
  final List<ServerConfig> unreachable;

  /// Servers that answered but refused the saved login (wrong or changed
  /// password) - a different fix from "can't reach", so a different note.
  final List<ServerConfig> rejected;

  const HomeFeed({
    required this.inProgress,
    required this.recent,
    required this.unreachable,
    this.rejected = const [],
  });
}

/// True when [e] means the server rejected our credentials rather than being
/// unreachable.
bool isLoginRejected(Object e) {
  if (e is DioException) {
    final code = e.response?.statusCode;
    if (code == 401 || code == 403) return true;
  }
  final m = e.toString().toLowerCase();
  return m.contains('401') || m.contains('unauthorized');
}

String seriesKey(String? serverId, String seriesId) => '${serverId ?? ''}|$seriesId';

/// Everything Home shows, from every configured server at once. Invalidate
/// to refresh.
final homeFeedProvider = FutureProvider<HomeFeed>((ref) async {
  final backends = await ref.watch(allBackendsProvider.future);
  final unreachable = <ServerConfig>[];
  final rejected = <ServerConfig>[];
  final inProgress = <FeedSeries>[];
  final newBooks = <(ReaderBackend, Book)>[];

  await Future.wait(backends.map((b) async {
    try {
      final results = await Future.wait([b.continueReading(), b.recentlyAdded()]);
      inProgress.addAll((results[0] as List<Series>).map((s) => FeedSeries(s, b)));
      newBooks.addAll((results[1] as List<Book>).take(40).map((bk) => (b, bk)));
    } catch (e) {
      (isLoginRejected(e) ? rejected : unreachable).add(b.config);
    }
  }));

  // Group by series (keeping the order each first appears - the backends
  // return newest first), per server. Then take turns between servers for the
  // 12 slots: one library with lots of new items must not crowd the others out.
  final groups = <String, List<(ReaderBackend, Book)>>{};
  final perServer = <String, List<List<(ReaderBackend, Book)>>>{};
  for (final r in newBooks) {
    final g = groups.putIfAbsent(seriesKey(r.$1.config.id, r.$2.seriesId), () {
      final fresh = <(ReaderBackend, Book)>[];
      perServer.putIfAbsent(r.$1.config.id, () => []).add(fresh);
      return fresh;
    });
    g.add(r);
  }
  final queues = perServer.values.toList();
  final picked = <List<(ReaderBackend, Book)>>[];
  for (var turn = 0; picked.length < 12 && queues.any((q) => q.isNotEmpty); turn++) {
    final q = queues[turn % queues.length];
    if (q.isNotEmpty) picked.add(q.removeAt(0));
  }
  final recent = await Future.wait(picked.map((g) async {
    final backend = g.first.$1;
    final latest = g.first.$2;
    Series? series;
    try {
      series = await backend.getSeries(latest.seriesId);
    } catch (_) {
      // Fall back to the chapter's own title below.
    }
    return FeedRecent(
      backend: backend,
      seriesId: latest.seriesId,
      seriesTitle: series?.title ?? latest.title,
      thumbnailUrl: series?.thumbnailUrl ?? latest.thumbnailUrl,
      latest: latest,
      count: g.length,
    );
  }));

  return HomeFeed(
    inProgress: inProgress,
    recent: recent,
    unreachable: unreachable,
    rejected: rejected,
  );
});

/// Most recently read first; series with no local history follow in the
/// server's own order. [activeServerId] stands in for legacy history entries
/// recorded before servers were tracked.
List<FeedSeries> orderByRecency(
  List<FeedSeries> items,
  List<HistoryEntry> history,
  String? activeServerId,
) {
  final last = lastReadByKey(history, activeServerId);
  final read = items.where((s) => last.containsKey(s.key)).toList()
    ..sort((a, b) => last[b.key]!.timestamp.compareTo(last[a.key]!.timestamp));
  return [...read, ...items.where((s) => !last.containsKey(s.key))];
}

/// The newest history entry per series, keyed by [seriesKey].
Map<String, HistoryEntry> lastReadByKey(
    List<HistoryEntry> history, String? activeServerId) {
  final out = <String, HistoryEntry>{};
  for (final e in history) {
    out.putIfAbsent(seriesKey(e.serverId ?? activeServerId, e.seriesId), () => e);
  }
  return out;
}

/// Zero-padded numbers ("002") from source libraries, cleaned for display
/// without losing a real fractional part ("3.5").
String formatChapterNumber(String raw) {
  final n = double.tryParse(raw);
  if (n == null) return raw;
  return n == n.roundToDouble() ? '${n.round()}' : '$n';
}
