import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
import '../../core/network/retry_interceptor.dart';

/// Where a chapter (our [Book]) lives, needed to build the ProgressDto
/// Kavita's `/api/Reader/progress` requires (chapterId, pageNum, seriesId,
/// volumeId, libraryId - all required). Populated whenever a chapter is
/// seen via [getBook] or [listBooks].
class _ChapterLocation {
  final String seriesId;
  final String volumeId;
  const _ChapterLocation(this.seriesId, this.volumeId);
}

/// Kavita REST API implementation of [ReaderBackend].
///
/// Verified against a live Kavita instance for auth, routing, pagination
/// envelope shape, and error responses. The account used for verification
/// had zero series indexed in any library, so response *field names* for
/// populated Series/Chapter payloads are best-effort from Kavita's public
/// API conventions rather than confirmed against real data - re-verify
/// field mapping once the library actually has content.
///
/// Kavita's "chapter" is our [Book]; there is no direct equivalent of
/// Komga's per-series book-count summary in the series list payload, so
/// [Series.booksCount]/[booksReadCount]/[booksUnreadCount] are 0 from
/// [listSeries] and only populated accurately by [getSeries].
class KavitaBackend implements ReaderBackend {
  @override
  final ServerConfig config;
  final String _password;
  final Dio _dio;

  String? _token;
  Future<void>? _loginFuture;

  final Map<String, _ChapterLocation> _chapterLocations = {};
  final Map<String, String> _seriesLibraryIds = {};

  KavitaBackend({required this.config, required String password, Dio? dio})
      : _password = password, // ignore: prefer_initializing_formals
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: config.baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (_token == null && !options.path.contains('Account/login')) {
          await _ensureLoggedIn();
        }
        if (_token != null) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final alreadyRetried = error.requestOptions.extra['retried'] == true;
        if (error.response?.statusCode == 401 &&
            !alreadyRetried &&
            !error.requestOptions.path.contains('Account/login')) {
          try {
            _token = null;
            _loginFuture = null;
            await _ensureLoggedIn();
            final opts = error.requestOptions;
            opts.headers['Authorization'] = 'Bearer $_token';
            opts.extra['retried'] = true;
            final response = await _dio.fetch(opts);
            return handler.resolve(response);
          } catch (_) {
            // Fall through to the original error.
          }
        }
        handler.next(error);
      },
    ));
    _dio.interceptors.add(RetryInterceptor(dio: _dio));
  }

  Future<void> _ensureLoggedIn() => _loginFuture ??= _login();

  Future<void> _login() async {
    final res = await _dio.post('/api/Account/login', data: {
      'username': config.username,
      'password': _password,
    });
    final data = res.data as Map<String, dynamic>;
    _token = data['token'] as String;
  }

  @override
  Future<void> authenticate() async {
    _token = null;
    _loginFuture = null;
    await _ensureLoggedIn();
  }

  @override
  Future<List<Library>> listLibraries() async {
    final res = await _dio.get('/api/Library/libraries');
    return (res.data as List)
        .map((e) => Library(
              id: '${e['id']}',
              name: e['name'] as String,
            ))
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
    // Kavita's all-v2 filter DTO shape isn't confirmed against real data;
    // fetch unfiltered pages and filter client-side rather than risk a
    // malformed filter body silently returning nothing.
    final res = await _dio.post(
      '/api/Series/all-v2',
      queryParameters: {'PageNumber': page + 1, 'PageSize': size},
      data: const <String, dynamic>{},
    );
    var items =
        (res.data as List).map((e) => _seriesFromJson(e)).toList();

    if (libraryId != null) {
      items = items.where((s) => s.libraryId == libraryId).toList();
    }
    if (unreadOnly) {
      items = items.where((s) => !s.isFullyRead).toList();
    }
    if (search != null && search.isNotEmpty) {
      final q = search.toLowerCase();
      items = items.where((s) => s.title.toLowerCase().contains(q)).toList();
    }

    final paginationHeader = res.headers.value('Pagination');
    var totalPages = 1;
    var totalElements = items.length;
    if (paginationHeader != null) {
      // {"currentPage":1,"itemsPerPage":20,"totalItems":0,"totalPages":0}
      final match = RegExp(r'"totalPages":(\d+)').firstMatch(paginationHeader);
      final totalMatch =
          RegExp(r'"totalItems":(\d+)').firstMatch(paginationHeader);
      if (match != null) totalPages = int.parse(match.group(1)!);
      if (totalMatch != null) totalElements = int.parse(totalMatch.group(1)!);
    }

    return PagedResult(
      items: items,
      page: page,
      size: size,
      totalPages: totalPages,
      totalElements: totalElements,
    );
  }

  Series _seriesFromJson(Map<String, dynamic> e) {
    final id = '${e['id']}';
    final libraryId = '${e['libraryId']}';
    _seriesLibraryIds[id] = libraryId;
    return Series(
      id: id,
      libraryId: libraryId,
      title: (e['name'] as String?) ?? 'Untitled',
      summary: e['summary'] as String?,
      booksCount: e['booksCount'] as int? ?? 0,
      booksReadCount: e['booksReadCount'] as int? ?? 0,
      booksUnreadCount: e['booksUnreadCount'] as int? ?? 0,
      thumbnailUrl: thumbnailUrlForSeries(id),
    );
  }

  @override
  Future<Series> getSeries(String id) async {
    final res = await _dio.get('/api/Series/$id');
    var series = _seriesFromJson(res.data as Map<String, dynamic>);

    // Backfill accurate book counts from the volumes/chapters we'd need
    // anyway for listBooks.
    final books = await listBooks(id);
    final read = books.where((b) => b.completed).length;
    series = Series(
      id: series.id,
      libraryId: series.libraryId,
      title: series.title,
      summary: series.summary,
      booksCount: books.length,
      booksReadCount: read,
      booksUnreadCount: books.length - read,
      thumbnailUrl: series.thumbnailUrl,
    );
    return series;
  }

  @override
  Future<List<Book>> listBooks(String seriesId) async {
    final res = await _dio
        .get('/api/Series/volumes', queryParameters: {'seriesId': seriesId});
    final volumes = res.data as List;
    final books = <Book>[];
    for (final v in volumes) {
      final volumeId = '${v['id']}';
      final chapters = (v['chapters'] as List?) ?? const [];
      for (final c in chapters) {
        books.add(_bookFromJson(c, seriesId, volumeId));
      }
    }
    books.sort((a, b) =>
        (double.tryParse(a.number) ?? 0).compareTo(double.tryParse(b.number) ?? 0));
    return books;
  }

  Book _bookFromJson(
      Map<String, dynamic> e, String seriesId, String volumeId) {
    final id = '${e['id']}';
    _chapterLocations[id] = _ChapterLocation(seriesId, volumeId);
    final pages = e['pages'] as int? ?? 0;
    final pagesRead = e['pagesRead'] as int? ?? 0;
    return Book(
      id: id,
      seriesId: seriesId,
      title: (e['titleName'] as String?) ??
          (e['title'] as String?) ??
          'Chapter ${e['number'] ?? ''}',
      number: '${e['number'] ?? e['chapterNumber'] ?? ''}',
      pageCount: pages,
      readProgressPage: pagesRead == 0 ? null : pagesRead - 1,
      completed: pages > 0 && pagesRead >= pages,
      thumbnailUrl: thumbnailUrlForBook(id),
    );
  }

  @override
  Future<Book> getBook(String id) async {
    final res =
        await _dio.get('/api/Chapter', queryParameters: {'chapterId': id});
    final data = res.data as Map<String, dynamic>;
    final seriesId = '${data['seriesId']}';
    final volumeId = '${data['volumeId']}';
    return _bookFromJson(data, seriesId, volumeId);
  }

  @override
  Future<Uri> pageUri(String bookId, int pageIndex) async {
    return Uri.parse(
        '${config.baseUrl}/api/Reader/image?chapterId=$bookId&page=$pageIndex&apiKey=');
  }

  @override
  Future<Uint8List> fetchPage(String bookId, int pageIndex) async {
    final res = await _dio.get<List<int>>(
      '/api/Reader/image',
      queryParameters: {'chapterId': bookId, 'page': pageIndex},
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data!);
  }

  Future<_ChapterLocation> _locate(String bookId) async {
    final cached = _chapterLocations[bookId];
    if (cached != null) return cached;
    await getBook(bookId);
    return _chapterLocations[bookId]!;
  }

  Future<String> _libraryIdFor(String seriesId) async {
    final cached = _seriesLibraryIds[seriesId];
    if (cached != null) return cached;
    final series = await getSeries(seriesId);
    return series.libraryId;
  }

  @override
  Future<void> updateProgress(
    String bookId, {
    required int page,
    bool completed = false,
  }) async {
    final location = await _locate(bookId);
    final libraryId = await _libraryIdFor(location.seriesId);

    await _dio.post('/api/Reader/progress', data: {
      'chapterId': int.parse(bookId),
      'pageNum': page,
      'seriesId': int.parse(location.seriesId),
      'volumeId': int.parse(location.volumeId),
      'libraryId': int.parse(libraryId),
    });

    if (completed) {
      await _dio.post('/api/Reader/mark-read',
          data: {'seriesId': int.parse(location.seriesId)});
    }
  }

  @override
  Future<List<Series>> continueReading() async {
    final res = await _dio.post(
      '/api/Series/on-deck',
      queryParameters: {'PageNumber': 1, 'PageSize': 20},
      data: const <String, dynamic>{},
    );
    return (res.data as List).map((e) => _seriesFromJson(e)).toList();
  }

  @override
  Future<List<Book>> recentlyAdded() async {
    final res = await _dio.post(
      '/api/Series/recently-added-v2',
      queryParameters: {'PageNumber': 1, 'PageSize': 10},
      data: const <String, dynamic>{},
    );
    final series = (res.data as List).map((e) => _seriesFromJson(e)).toList();

    final books = <Book>[];
    for (final s in series) {
      final seriesBooks = await listBooks(s.id);
      if (seriesBooks.isNotEmpty) books.add(seriesBooks.first);
    }
    return books;
  }

  @override
  Future<List<Collection>> listCollections() async {
    final res = await _dio.get('/api/Collection');
    return (res.data as List)
        .map((e) => Collection(
              id: '${e['id']}',
              name: e['title'] as String? ?? e['name'] as String? ?? '',
              seriesCount: e['itemCount'] as int? ?? 0,
            ))
        .toList();
  }

  @override
  Future<List<ReadList>> listReadLists() async {
    final res = await _dio.post('/api/ReadingList/lists',
        data: const <String, dynamic>{});
    return (res.data as List)
        .map((e) => ReadList(
              id: '${e['id']}',
              name: e['title'] as String? ?? '',
              bookCount: e['itemCount'] as int? ?? 0,
            ))
        .toList();
  }

  @override
  String thumbnailUrlForSeries(String seriesId) =>
      '${config.baseUrl}/api/Image/series-cover?seriesId=$seriesId';

  @override
  String thumbnailUrlForBook(String bookId) =>
      '${config.baseUrl}/api/Image/chapter-cover?chapterId=$bookId';

  @override
  Map<String, String> get imageHeaders =>
      _token == null ? const {} : {'Authorization': 'Bearer $_token'};
}
