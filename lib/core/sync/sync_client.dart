import 'package:dio/dio.dart';

/// One record as the sync service stores/returns it - a JSON blob plus
/// the bookkeeping fields the server uses for last-write-wins merging.
class SyncRecord {
  final String recordId;
  final Map<String, dynamic> data;
  final String updatedAt;
  final bool deleted;

  const SyncRecord({
    required this.recordId,
    required this.data,
    required this.updatedAt,
    this.deleted = false,
  });

  factory SyncRecord.fromJson(Map<String, dynamic> json) => SyncRecord(
        recordId: json['record_id'] as String,
        data: json['data'] as Map<String, dynamic>,
        updatedAt: json['updated_at'] as String,
        deleted: json['deleted'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'record_id': recordId,
        'data': data,
        'updated_at': updatedAt,
        'deleted': deleted,
      };
}

class SyncAuthException implements Exception {
  final String message;
  const SyncAuthException(this.message);
  @override
  String toString() => message;
}

/// Thin client over the shaddai-sync API (`deploy/sync-service/main.py`) -
/// same constructor/interceptor shape as [KapowarrClient]: a base URL plus
/// an interceptor that attaches auth, here a bearer token instead of an
/// api_key query parameter.
class SyncClient {
  final Dio _dio;
  String? _token;

  SyncClient({required String baseUrl, String? token, Dio? dio})
      : _token = token, // ignore: prefer_initializing_formals
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 15),
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        handler.next(options);
      },
    ));
  }

  /// Same-origin default when served from reader.shaddai.home, matching
  /// the `_sameOriginDefaultUrl` pattern used for Kapowarr/other servers -
  /// falls back to the raw Tailscale address otherwise (local dev, or the
  /// app served from somewhere else on the tailnet).
  static String defaultBaseUrl() {
    if (Uri.base.host == 'reader.shaddai.home') {
      return '${Uri.base.origin}/sync';
    }
    return 'http://100.108.109.63:8600';
  }

  void updateToken(String? token) {
    _token = token;
  }

  Future<({String token, String username})> register({
    required String username,
    required String password,
    required String inviteCode,
  }) async {
    final res = await _dio.post('/auth/register', data: {
      'username': username,
      'password': password,
      'invite_code': inviteCode,
    });
    final data = res.data as Map<String, dynamic>;
    return (token: data['token'] as String, username: data['username'] as String);
  }

  Future<({String token, String username})> login({
    required String username,
    required String password,
  }) async {
    final res = await _dio.post('/auth/login', data: {
      'username': username,
      'password': password,
    });
    final data = res.data as Map<String, dynamic>;
    return (token: data['token'] as String, username: data['username'] as String);
  }

  Future<void> logout() async {
    await _dio.post('/auth/logout');
  }

  Future<String> me() async {
    final res = await _dio.get('/auth/me');
    return (res.data as Map<String, dynamic>)['username'] as String;
  }

  Future<List<SyncRecord>> pull(String resource, {String since = ''}) async {
    final res = await _dio.get('/records/$resource', queryParameters: {
      if (since.isNotEmpty) 'since': since,
    });
    final records = (res.data as Map<String, dynamic>)['records'] as List;
    return records
        .map((e) => SyncRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<SyncRecord>> push(String resource, List<SyncRecord> records) async {
    final res = await _dio.put('/records/$resource',
        data: records.map((r) => r.toJson()).toList());
    final result = (res.data as Map<String, dynamic>)['records'] as List;
    return result
        .map((e) => SyncRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
