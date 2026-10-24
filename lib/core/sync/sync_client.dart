import 'package:dio/dio.dart';

import '../debug/debug_log.dart';

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

/// A single-use code the owner gave one friend (sync service `/admin/invites`).
class Invite {
  final String code;
  final String note;
  final String link;

  /// "unused", "used" or "revoked".
  final String status;
  final String? usedBy;

  const Invite({
    required this.code,
    required this.note,
    required this.link,
    required this.status,
    this.usedBy,
  });

  factory Invite.fromJson(Map<String, dynamic> j) => Invite(
        code: j['code'] as String,
        note: j['note'] as String? ?? '',
        link: j['link'] as String,
        status: j['status'] as String,
        usedBy: j['used_by'] as String?,
      );
}

/// A friend's request for a series (sync service `/requests`).
class SeriesRequest {
  final int id;
  final String title;
  final int? comicvineId;
  final int? year;
  final String? coverLink;

  /// "waiting", "added" or "declined".
  final String status;

  /// Who asked; only filled in the owner's list.
  final String? username;

  const SeriesRequest({
    required this.id,
    required this.title,
    required this.status,
    this.comicvineId,
    this.year,
    this.coverLink,
    this.username,
  });

  factory SeriesRequest.fromJson(Map<String, dynamic> j) => SeriesRequest(
        id: j['id'] as int,
        title: j['title'] as String,
        status: j['status'] as String,
        comicvineId: j['comicvine_id'] as int?,
        year: j['year'] as int?,
        coverLink: j['cover_link'] as String?,
        username: j['username'] as String?,
      );
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
            trackedDio(BaseOptions(
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

  /// The public sync address: what installed apps use unless the sign-in
  /// screen was given another one (saved in [AuthStore]).
  static const publicUrl = 'https://reader.shaddaicommunications.com/sync';

  /// Same-origin when the web app is served from one of our hosts, the
  /// public address everywhere else. No Tailscale address: friends and a
  /// tablet without the VPN must be able to sign in.
  static String defaultBaseUrl() {
    if (const {'reader.shaddai.home', 'reader.shaddaicommunications.com'}.contains(Uri.base.host)) {
      return '${Uri.base.origin}/sync';
    }
    return publicUrl;
  }

  /// What someone types into the sync server field, made usable:
  /// `https://` added when there's no scheme, trailing slashes dropped.
  /// Null for blank input.
  static String? normalizeUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return null;
    if (!url.contains('://')) url = 'https://$url';
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  String get baseUrl => _dio.options.baseUrl;
  set baseUrl(String url) => _dio.options.baseUrl = url;

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

  /// The signed-in account. A sync service from before roles sends no
  /// `role`; that account is the owner, so nothing hides on an old server.
  /// [komga] is the Komga login the service made for a friend at sign-up.
  Future<({String username, bool isOwner, ({String url, String username})? komga})>
      me() async {
    final data = (await _dio.get('/auth/me')).data as Map<String, dynamic>;
    final k = data['komga'] as Map<String, dynamic>?;
    return (
      username: data['username'] as String,
      isOwner: (data['role'] as String? ?? 'owner') == 'owner',
      komga: k == null
          ? null
          : (url: k['url'] as String, username: k['username'] as String),
    );
  }

  /// Kapowarr search run by the service with the owner's key, so friends
  /// can search without it (results have Kapowarr's own JSON shape).
  Future<List<Map<String, dynamic>>> kapowarrSearch(String query) async {
    final res = await _dio.get('/kapowarr/search', queryParameters: {'q': query});
    return ((res.data as Map<String, dynamic>)['results'] as List)
        .cast<Map<String, dynamic>>();
  }

  /// A friend asking for a series; the owner approves it.
  Future<SeriesRequest> createRequest({
    required String title,
    int? comicvineId,
    int? year,
    String? coverLink,
  }) async {
    final res = await _dio.post('/requests', data: {
      'title': title,
      'comicvine_id': ?comicvineId,
      'year': ?year,
      'cover_link': ?coverLink,
    });
    return SeriesRequest.fromJson(res.data as Map<String, dynamic>);
  }

  /// Your own requests, or with [all] (owner only) everyone's.
  Future<List<SeriesRequest>> requests({bool all = false}) async {
    final res = await _dio.get(all ? '/admin/requests' : '/requests');
    return ((res.data as Map<String, dynamic>)['requests'] as List)
        .map((r) => SeriesRequest.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Owner: marks a request "added" or "declined".
  Future<void> decideRequest(int id, String status) async {
    await _dio.patch('/admin/requests/$id', data: {'status': status});
  }

  /// Owner only: a fresh single-use code, [note] says who it's for.
  Future<Invite> createInvite(String note) async {
    final res = await _dio.post('/admin/invites', data: {'note': note});
    return Invite.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<Invite>> invites() async {
    final res = await _dio.get('/admin/invites');
    return ((res.data as Map<String, dynamic>)['invites'] as List)
        .map((e) => Invite.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Only unused codes can be revoked; a used one already became an account.
  Future<void> revokeInvite(String code) async {
    await _dio.delete('/admin/invites/$code');
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
