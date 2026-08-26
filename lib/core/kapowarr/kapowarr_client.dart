import 'package:dio/dio.dart';

import 'kapowarr_config.dart';

class KapowarrStats {
  final int volumes;
  final int monitored;
  final int issues;
  final int downloadedIssues;
  final int files;
  final int totalFileSize;

  const KapowarrStats({
    required this.volumes,
    required this.monitored,
    required this.issues,
    required this.downloadedIssues,
    required this.files,
    required this.totalFileSize,
  });

  factory KapowarrStats.fromJson(Map<String, dynamic> json) => KapowarrStats(
        volumes: json['volumes'] as int? ?? 0,
        monitored: json['monitored'] as int? ?? 0,
        issues: json['issues'] as int? ?? 0,
        downloadedIssues: json['downloaded_issues'] as int? ?? 0,
        files: json['files'] as int? ?? 0,
        totalFileSize: json['total_file_size'] as int? ?? 0,
      );
}

class KapowarrQueueItem {
  final String title;
  final String source;

  const KapowarrQueueItem({required this.title, required this.source});

  factory KapowarrQueueItem.fromJson(Map<String, dynamic> json) =>
      KapowarrQueueItem(
        title: (json['web_title'] as String?) ??
            (json['file_title'] as String?) ??
            'Unknown',
        source: json['source'] as String? ?? '',
      );
}

class KapowarrHistoryItem {
  final String title;
  final String source;
  final bool success;
  final DateTime downloadedAt;

  const KapowarrHistoryItem({
    required this.title,
    required this.source,
    required this.success,
    required this.downloadedAt,
  });

  factory KapowarrHistoryItem.fromJson(Map<String, dynamic> json) =>
      KapowarrHistoryItem(
        title: (json['web_title'] as String?) ??
            (json['file_title'] as String?) ??
            'Unknown',
        source: json['source'] as String? ?? '',
        success: json['success'] as bool? ?? true,
        downloadedAt: DateTime.fromMillisecondsSinceEpoch(
            (json['downloaded_at'] as int? ?? 0) * 1000),
      );
}

class KapowarrIssue {
  final int id;
  final String issueNumber;
  final String? title;
  final String? date;
  final bool monitored;
  final bool hasFile;

  const KapowarrIssue({
    required this.id,
    required this.issueNumber,
    this.title,
    this.date,
    required this.monitored,
    required this.hasFile,
  });

  factory KapowarrIssue.fromJson(Map<String, dynamic> json) => KapowarrIssue(
        id: json['id'] as int,
        issueNumber: (json['issue_number'] as String?) ?? '?',
        title: json['title'] as String?,
        date: json['date'] as String?,
        monitored: json['monitored'] as bool? ?? false,
        hasFile: (json['files'] as List?)?.isNotEmpty ?? false,
      );
}

class KapowarrVolume {
  final int id;
  final String title;
  final int year;
  final String publisher;
  final int volumeNumber;
  final bool monitored;
  final int issueCount;
  final int issuesDownloaded;
  final String folder;
  final List<KapowarrIssue> issues;

  const KapowarrVolume({
    required this.id,
    required this.title,
    required this.year,
    required this.publisher,
    required this.volumeNumber,
    required this.monitored,
    required this.issueCount,
    required this.issuesDownloaded,
    required this.folder,
    this.issues = const [],
  });

  factory KapowarrVolume.fromJson(Map<String, dynamic> json) => KapowarrVolume(
        id: json['id'] as int,
        title: json['title'] as String? ?? 'Untitled',
        year: json['year'] as int? ?? 0,
        publisher: json['publisher'] as String? ?? '',
        volumeNumber: json['volume_number'] as int? ?? 1,
        monitored: json['monitored'] as bool? ?? false,
        issueCount: json['issue_count'] as int? ?? 0,
        issuesDownloaded: json['issues_downloaded'] as int? ?? 0,
        folder: json['folder'] as String? ?? '',
        issues: (json['issues'] as List?)
                ?.map((e) => KapowarrIssue.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

/// Thin client over Kapowarr's REST API, used only for the read-only
/// status view - Shaddai Reader never triggers downloads or edits volumes.
class KapowarrClient {
  final Dio _dio;
  final String _apiKey;

  KapowarrClient({required KapowarrConfig config, Dio? dio})
      : _apiKey = config.apiKey,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: config.baseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 15),
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.queryParameters['api_key'] = _apiKey;
        handler.next(options);
      },
    ));
  }

  Future<KapowarrStats> getStats() async {
    final res = await _dio.get('/api/volumes/stats');
    return KapowarrStats.fromJson(
        (res.data as Map<String, dynamic>)['result'] as Map<String, dynamic>);
  }

  Future<List<KapowarrQueueItem>> getQueue() async {
    final res = await _dio.get('/api/activity/queue');
    final result = (res.data as Map<String, dynamic>)['result'] as List;
    return result
        .map((e) => KapowarrQueueItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<KapowarrHistoryItem>> getHistory({int limit = 10}) async {
    final res = await _dio.get('/api/activity/history');
    final result = (res.data as Map<String, dynamic>)['result'] as List;
    return result
        .take(limit)
        .map((e) => KapowarrHistoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// All volumes Kapowarr is tracking, without their issue lists (issues
  /// come from [getVolume] to keep this list call cheap).
  Future<List<KapowarrVolume>> getVolumes() async {
    final res = await _dio.get('/api/volumes');
    final result = (res.data as Map<String, dynamic>)['result'] as List;
    return result
        .map((e) => KapowarrVolume.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<KapowarrVolume> getVolume(int id) async {
    final res = await _dio.get('/api/volumes/$id');
    return KapowarrVolume.fromJson(
        (res.data as Map<String, dynamic>)['result'] as Map<String, dynamic>);
  }
}
