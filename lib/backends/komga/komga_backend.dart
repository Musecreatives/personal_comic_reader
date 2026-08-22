import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
import '../../core/network/retry_interceptor.dart';

/// Komga REST v1 implementation of [ReaderBackend].
///
/// Auth is HTTP Basic on every request (Komga has no token endpoint for
/// this use case), attached via a dio interceptor so callers never touch
/// headers directly.
class KomgaBackend implements ReaderBackend {
  @override
  final ServerConfig config;
  final String _password;
  final Dio _dio;

  /// [dio] is injectable for tests; production code should leave it null
  /// and let the backend build its own configured client.
  KomgaBackend({required this.config, required String password, Dio? dio})
      : _password = password, // ignore: prefer_initializing_formals
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: config.baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            )) {
    final authHeader =
        'Basic ${base64Encode(utf8.encode('${config.username}:$_password'))}';
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers['Authorization'] = authHeader;
        handler.next(options);
      },
    ));
    _dio.interceptors.add(RetryInterceptor(dio: _dio));
  }

  @override
  Future<void> authenticate() async {
    // Komga has no dedicated login call - validate creds against a cheap,
    // always-available endpoint instead.
    await _dio.get('/api/v2/users/me');
  }

  @override
  Future<List<Library>> listLibraries() async {
    final res = await _dio.get('/api/v1/libraries');
    return (res.data as List)
        .map((e) => Library(id: e['id'] as String, name: e['name'] as String))
        .toList();
  }

  @override
  Future<PagedResult<Series>> listSeries({
    String? libraryId,
    int page = 0,
    int size = 20,
    SeriesSort sort = SeriesSort.title,
    SortDirection direction = SortDirection.asc,
    bool unreadOnly = false,
    String? search,
  }) async {
    final sortParam = '${_sortField(sort)},${direction.name}';
    final res = await _dio.post(
      '/api/v1/series/list',
      queryParameters: {
        'page': page,
        'size': size,
        'sort': sortParam,
      },
      data: {
        if (libraryId != null)
          'condition': {
            'allOf': [
              {
                'libraryId': {'operator': 'is', 'value': libraryId}
              },
              if (unreadOnly)
                {
                  'readStatus': {'operator': 'is', 'value': 'UNREAD'}
                },
              if (search != null && search.isNotEmpty)
                {
                  'seriesTitle': {'operator': 'matches', 'value': search}
                },
            ],
          }
        else if (unreadOnly || (search != null && search.isNotEmpty))
          'condition': {
            'allOf': [
              if (unreadOnly)
                {
                  'readStatus': {'operator': 'is', 'value': 'UNREAD'}
                },
              if (search != null && search.isNotEmpty)
                {
                  'seriesTitle': {'operator': 'matches', 'value': search}
                },
            ],
          },
      },
    );
    final data = res.data as Map<String, dynamic>;
    final content = data['content'] as List;
    return PagedResult(
      items: content.map((e) => _seriesFromJson(e)).toList(),
      page: data['number'] as int,
      size: data['size'] as int,
      totalPages: data['totalPages'] as int,
      totalElements: data['totalElements'] as int,
    );
  }

  String _sortField(SeriesSort sort) {
    switch (sort) {
      case SeriesSort.title:
        return 'metadata.titleSort';
      case SeriesSort.dateAdded:
        return 'createdDate';
      case SeriesSort.dateUpdated:
        return 'lastModifiedDate';
      case SeriesSort.releaseDate:
        return 'booksMetadata.releaseDate';
    }
  }

  @override
  Future<Series> getSeries(String id) async {
    final res = await _dio.get('/api/v1/series/$id');
    return _seriesFromJson(res.data as Map<String, dynamic>);
  }

  Series _seriesFromJson(Map<String, dynamic> e) {
    final metadata = e['metadata'] as Map<String, dynamic>?;
    final booksMetadata = e['booksMetadata'] as Map<String, dynamic>?;
    return Series(
      id: e['id'] as String,
      libraryId: e['libraryId'] as String,
      title: (metadata?['title'] as String?) ?? e['name'] as String,
      summary: booksMetadata?['summary'] as String?,
      booksCount: e['booksCount'] as int,
      booksReadCount: e['booksReadCount'] as int,
      booksUnreadCount: e['booksUnreadCount'] as int,
      thumbnailUrl: thumbnailUrlForSeries(e['id'] as String),
    );
  }

  @override
  Future<List<Book>> listBooks(String seriesId) async {
    final res = await _dio.get(
      '/api/v1/series/$seriesId/books',
      queryParameters: {'size': 500, 'sort': 'metadata.numberSort,asc'},
    );
    final content = (res.data as Map<String, dynamic>)['content'] as List;
    return content.map((e) => _bookFromJson(e)).toList();
  }

  @override
  Future<Book> getBook(String id) async {
    final res = await _dio.get('/api/v1/books/$id');
    return _bookFromJson(res.data as Map<String, dynamic>);
  }

  Book _bookFromJson(Map<String, dynamic> e) {
    final metadata = e['metadata'] as Map<String, dynamic>?;
    final readProgress = e['readProgress'] as Map<String, dynamic>?;
    return Book(
      id: e['id'] as String,
      seriesId: e['seriesId'] as String,
      title: (metadata?['title'] as String?) ?? e['name'] as String,
      number: (metadata?['number'] as String?) ?? '',
      pageCount: e['media']?['pagesCount'] as int? ?? 0,
      readProgressPage: readProgress?['page'] as int?,
      completed: readProgress?['completed'] as bool? ?? false,
      thumbnailUrl: thumbnailUrlForBook(e['id'] as String),
    );
  }

  @override
  Future<Uri> pageUri(String bookId, int pageIndex) async {
    // Komga page numbers are 1-based.
    return Uri.parse(
        '${config.baseUrl}/api/v1/books/$bookId/pages/${pageIndex + 1}');
  }

  @override
  Future<Uint8List> fetchPage(String bookId, int pageIndex) async {
    final res = await _dio.get<List<int>>(
      '/api/v1/books/$bookId/pages/${pageIndex + 1}',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data!);
  }

  @override
  Future<void> updateProgress(
    String bookId, {
    required int page,
    bool completed = false,
  }) async {
    await _dio.patch(
      '/api/v1/books/$bookId/read-progress',
      data: {'page': page + 1, 'completed': completed},
    );
  }

  @override
  Future<List<Series>> continueReading() async {
    final res = await _dio.get(
      '/api/v1/series',
      queryParameters: {'sort': 'lastModifiedDate,desc', 'size': 20},
    );
    final content = (res.data as Map<String, dynamic>)['content'] as List;
    return content
        .map((e) => _seriesFromJson(e))
        .where((s) => !s.isFullyRead && s.booksReadCount > 0)
        .toList();
  }

  @override
  Future<List<Book>> recentlyAdded() async {
    final res = await _dio.get(
      '/api/v1/books/latest',
      queryParameters: {'size': 20},
    );
    final content = (res.data as Map<String, dynamic>)['content'] as List;
    return content.map((e) => _bookFromJson(e)).toList();
  }

  @override
  Future<List<Collection>> listCollections() async {
    final res = await _dio.get('/api/v1/collections');
    final content = (res.data as Map<String, dynamic>)['content'] as List;
    return content
        .map((e) => Collection(
              id: e['id'] as String,
              name: e['name'] as String,
              seriesCount: (e['seriesIds'] as List).length,
            ))
        .toList();
  }

  @override
  Future<List<ReadList>> listReadLists() async {
    final res = await _dio.get('/api/v1/readlists');
    final content = (res.data as Map<String, dynamic>)['content'] as List;
    return content
        .map((e) => ReadList(
              id: e['id'] as String,
              name: e['name'] as String,
              bookCount: (e['bookIds'] as List).length,
            ))
        .toList();
  }

  @override
  String thumbnailUrlForSeries(String seriesId) =>
      '${config.baseUrl}/api/v1/series/$seriesId/thumbnail';

  @override
  String thumbnailUrlForBook(String bookId) =>
      '${config.baseUrl}/api/v1/books/$bookId/thumbnail';

  @override
  Map<String, String> get imageHeaders => {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${config.username}:$_password'))}',
      };
}
