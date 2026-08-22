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
}
