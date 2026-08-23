import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';

import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
import '../../core/network/retry_interceptor.dart';
import 'opds_atom.dart';

class _BookInfo {
  final String title;
  final String seriesId;
  final AtomLink? pseStream;
  final AtomLink? acquisition;
  final String? thumbnailUrl;

  const _BookInfo({
    required this.title,
    required this.seriesId,
    this.pseStream,
    this.acquisition,
    this.thumbnailUrl,
  });
}

/// A downloaded-and-unzipped CBZ, cached in memory so repeated page reads
/// (and the reader's prefetch) don't re-download and re-unzip.
class _LoadedArchive {
  final List<Uint8List> pages;
  const _LoadedArchive(this.pages);
}

/// Generic OPDS 1.2 (+ OPDS-PSE) implementation of [ReaderBackend].
///
/// Works against *any* OPDS 1.2 catalog, not just Komga's - which is why
/// its model mapping is looser than the other backends: a "library" here
/// is just whatever top-level navigation entries the root catalog
/// happens to expose, and a "series" is any navigation entry one level
/// in. Page streaming prefers OPDS-PSE (`pse:count` + a `{pageNumber}`
/// href template) when a book's feed entry advertises it; otherwise the
/// whole acquisition file is downloaded once and unzipped as a CBZ
/// in-app via `package:archive` (web-safe - no native unzip dependency).
///
/// Book/series identity is feed-URL-based (OPDS has no stable numeric
/// IDs), cached internally as entries are encountered via [listSeries]/
/// [listBooks] - calling [getBook] or [fetchPage] for a book this
/// instance hasn't seen yet throws, same tradeoff already made for
/// Kavita's chapter-location cache and Suwayomi's chapter-to-manga cache.
class OpdsBackend implements ReaderBackend {
  @override
  final ServerConfig config;
  final String _password;
  final Dio _dio;

  final Map<String, _BookInfo> _books = {};
  final Map<String, String> _nextPageUrls = {};
  final Map<String, _LoadedArchive> _archives = {};

  OpdsBackend({required this.config, required String password, Dio? dio})
      : _password = password, // ignore: prefer_initializing_formals
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
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

  String get _rootUrl => config.baseUrl;

  Future<AtomFeed> _fetchFeed(String url) async {
    final res = await _dio.get<String>(url,
        options: Options(responseType: ResponseType.plain));
    return AtomFeed.parse(res.data!);
  }

  @override
  Future<void> authenticate() async {
    await _fetchFeed(_rootUrl);
  }

  @override
  Future<List<Library>> listLibraries() async {
    final feed = await _fetchFeed(_rootUrl);
    return feed.entries
        .where((e) => e.subsectionLink != null)
        .map((e) => Library(id: e.subsectionLink!.href, name: e.title))
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
    final feedUrl = page == 0
        ? (libraryId ?? _rootUrl)
        : _nextPageUrls['${libraryId ?? _rootUrl}#${page - 1}'];
    if (feedUrl == null) {
      return PagedResult(items: const [], page: page, size: size, totalPages: page, totalElements: 0);
    }

    final feed = await _fetchFeed(feedUrl);
    if (feed.nextHref != null) {
      _nextPageUrls['${libraryId ?? _rootUrl}#$page'] = feed.nextHref!;
    }

    var items = feed.entries
        .where((e) => e.isNavigation)
        .map((e) => Series(
              id: e.subsectionLink!.href,
              libraryId: libraryId ?? _rootUrl,
              title: e.title,
              summary: e.content,
              booksCount: 0,
              booksReadCount: 0,
              booksUnreadCount: 0,
              thumbnailUrl: e.thumbnailLink?.href,
            ))
        .toList();

    if (search != null && search.isNotEmpty) {
      final q = search.toLowerCase();
      items = items.where((s) => s.title.toLowerCase().contains(q)).toList();
    }

    return PagedResult(
      items: items,
      page: page,
      size: size,
      totalPages: feed.nextHref != null ? page + 2 : page + 1,
      totalElements: items.length,
    );
  }

  @override
  Future<Series> getSeries(String id) async {
    final feed = await _fetchFeed(id);
    final bookCount = feed.entries.where((e) => e.isBook).length;
    return Series(
      id: id,
      libraryId: '',
      title: feed.title,
      summary: feed.subtitle,
      booksCount: bookCount,
      booksReadCount: 0,
      booksUnreadCount: bookCount,
      thumbnailUrl: null,
    );
  }

  @override
  Future<List<Book>> listBooks(String seriesId) async {
    final feed = await _fetchFeed(seriesId);
    final books = <Book>[];
    for (final entry in feed.entries.where((e) => e.isBook)) {
      final bookId = entry.id;
      _books[bookId] = _BookInfo(
        title: entry.title,
        seriesId: seriesId,
        pseStream: entry.pseStreamLink,
        acquisition: entry.acquisitionLink,
        thumbnailUrl: entry.thumbnailLink?.href,
      );
      final pseCount = entry.pseStreamLink?.pseCount;
      books.add(Book(
        id: bookId,
        seriesId: seriesId,
        title: entry.title,
        number: '',
        pageCount: pseCount ?? 0,
        completed: false,
        thumbnailUrl: entry.thumbnailLink?.href,
      ));
    }
    return books;
  }

  @override
  Future<Book> getBook(String id) async {
    final info = _books[id];
    if (info == null) {
      throw StateError(
          'Unknown OPDS book "$id" - open it via its series first.');
    }
    var pageCount = info.pseStream?.pseCount ?? 0;
    if (pageCount == 0 && info.acquisition != null) {
      final archive = await _ensureArchiveLoaded(id);
      pageCount = archive.pages.length;
    }
    return Book(
      id: id,
      seriesId: info.seriesId,
      title: info.title,
      number: '',
      pageCount: pageCount,
      completed: false,
      thumbnailUrl: info.thumbnailUrl,
    );
  }

  Future<_LoadedArchive> _ensureArchiveLoaded(String bookId) async {
    final cached = _archives[bookId];
    if (cached != null) return cached;

    final info = _books[bookId];
    if (info?.acquisition == null) {
      throw StateError('No acquisition link for OPDS book "$bookId"');
    }

    final res = await _dio.get<List<int>>(
      info!.acquisition!.href,
      options: Options(responseType: ResponseType.bytes),
    );
    final archive = ZipDecoder().decodeBytes(res.data!);
    final imageFiles = archive.files
        .where((f) => f.isFile && _isImage(f.name))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final pages = imageFiles
        .map((f) => Uint8List.fromList(f.content as List<int>))
        .toList();
    final loaded = _LoadedArchive(pages);
    _archives[bookId] = loaded;
    return loaded;
  }

  bool _isImage(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }

  @override
  Future<Uri> pageUri(String bookId, int pageIndex) async {
    final info = _books[bookId];
    final template = info?.pseStream?.href;
    if (template != null) {
      return Uri.parse(template.replaceAll('{pageNumber}', '$pageIndex'));
    }
    throw StateError('No page-streaming URL for OPDS book "$bookId" - it '
        'uses the CBZ fallback, which has no per-page URL.');
  }

  @override
  Future<Uint8List> fetchPage(String bookId, int pageIndex) async {
    final info = _books[bookId];
    if (info == null) {
      throw StateError(
          'Unknown OPDS book "$bookId" - open it via its series first.');
    }

    final pseTemplate = info.pseStream?.href;
    if (pseTemplate != null) {
      final url = pseTemplate.replaceAll('{pageNumber}', '$pageIndex');
      final res = await _dio.get<List<int>>(url,
          options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(res.data!);
    }

    final archive = await _ensureArchiveLoaded(bookId);
    if (pageIndex < 0 || pageIndex >= archive.pages.length) {
      throw RangeError.index(pageIndex, archive.pages, 'pageIndex');
    }
    return archive.pages[pageIndex];
  }

  @override
  Future<void> updateProgress(
    String bookId, {
    required int page,
    bool completed = false,
  }) async {
    // OPDS 1.2 has no standard progress-tracking endpoint; OPDS-PSE only
    // advertises pse:lastRead, it doesn't define a way to write it back.
    // Progress for OPDS-backed servers is tracked locally only (still
    // covered by the same offline queue/local settings as every other
    // backend - just never synced server-side).
  }

  @override
  Future<List<Series>> continueReading() async => const [];

  @override
  Future<List<Book>> recentlyAdded() async => const [];

  @override
  Future<List<Collection>> listCollections() async => const [];

  @override
  Future<List<ReadList>> listReadLists() async => const [];

  @override
  String thumbnailUrlForSeries(String seriesId) => '';

  @override
  String thumbnailUrlForBook(String bookId) => _books[bookId]?.thumbnailUrl ?? '';

  @override
  Map<String, String> get imageHeaders => {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${config.username}:$_password'))}',
      };
}
