import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
import '../../core/network/retry_interceptor.dart';

/// Suwayomi (Tachidesk) GraphQL implementation of [ReaderBackend].
///
/// Verified against a live instance with real content. No login is
/// required by Suwayomi itself (it's typically run behind Tailscale/a
/// trusted network); `config.username`/password are unused.
///
/// Maps our model onto Suwayomi's: a [Library] is a Category, a [Series]
/// is a Manga, and a [Book] is a Chapter. Collections and reading lists
/// have no Suwayomi equivalent distinct from categories (already used as
/// libraries), so both return empty lists.
class SuwayomiBackend implements ReaderBackend {
  @override
  final ServerConfig config;
  final Dio _dio;

  final Set<String> _fetchedChapters = {};
  final Map<String, String> _chapterMangaId = {};
  // Suwayomi's REST page-serving route (/api/v1/manga/{id}/chapter/{N}/page/{i})
  // takes each chapter's *sourceOrder* - its 1-based position within the
  // manga's chapter list - not its GraphQL database id. The two only
  // coincide by chance for a manga's very first chapter; anything with
  // split/special chapters (22.1, 22.2, ...) diverges immediately.
  // Verified live: chapter id 326 (chapterNumber 22.1) serves at
  // .../chapter/23/... where 23 is its sourceOrder, and 404s at any other
  // path segment.
  final Map<String, int> _chapterSourceOrder = {};

  SuwayomiBackend({required this.config, required String password, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: config.baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            )) {
    _dio.interceptors.add(RetryInterceptor(dio: _dio));
  }

  Future<Map<String, dynamic>> _gql(
    String query, [
    Map<String, dynamic>? variables,
  ]) async {
    final res = await _dio.post('/api/graphql', data: {
      'query': query,
      'variables': ?variables,
    });
    final data = res.data as Map<String, dynamic>;
    if (data['errors'] != null) {
      throw Exception('Suwayomi GraphQL error: ${data['errors']}');
    }
    return data['data'] as Map<String, dynamic>;
  }

  @override
  Future<void> authenticate() async {
    await _gql('{ categories { nodes { id } } }');
  }

  @override
  Future<List<Library>> listLibraries() async {
    final data = await _gql('{ categories { nodes { id name } } }');
    final nodes = data['categories']['nodes'] as List;
    return nodes
        .map((e) => Library(id: '${e['id']}', name: e['name'] as String))
        .toList();
  }

  static const _mangaFields =
      'id title thumbnailUrl inLibrary unreadCount chapters { totalCount }';

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
    List<dynamic> nodes;
    if (libraryId != null) {
      final data = await _gql(
        'query(\$id: Int!) { category(id: \$id) { mangas { nodes { $_mangaFields } } } }',
        {'id': int.parse(libraryId)},
      );
      nodes = data['category']['mangas']['nodes'] as List;
    } else {
      final data = await _gql(
        '{ mangas(condition: {inLibrary: true}) { nodes { $_mangaFields } } }',
      );
      nodes = data['mangas']['nodes'] as List;
    }

    var items = nodes.map((e) => _seriesFromJson(e)).toList();
    if (unreadOnly) {
      items = items.where((s) => !s.isFullyRead).toList();
    }
    if (search != null && search.isNotEmpty) {
      final q = search.toLowerCase();
      items = items.where((s) => s.title.toLowerCase().contains(q)).toList();
    }

    final start = (page * size).clamp(0, items.length);
    final end = (start + size).clamp(0, items.length);
    return PagedResult(
      items: items.sublist(start, end),
      page: page,
      size: size,
      totalPages: (items.length / size).ceil().clamp(1, 1 << 30),
      totalElements: items.length,
    );
  }

  Series _seriesFromJson(Map<String, dynamic> e) {
    final total = e['chapters']?['totalCount'] as int? ?? 0;
    final unread = e['unreadCount'] as int? ?? 0;
    final id = '${e['id']}';
    return Series(
      id: id,
      libraryId: '',
      title: e['title'] as String? ?? 'Untitled',
      summary: e['description'] as String?,
      booksCount: total,
      booksReadCount: total - unread,
      booksUnreadCount: unread,
      thumbnailUrl: thumbnailUrlForSeries(id),
    );
  }

  @override
  Future<Series> getSeries(String id) async {
    final data = await _gql(
      'query(\$id: Int!) { manga(id: \$id) { id title description thumbnailUrl unreadCount chapters { totalCount } } }',
      {'id': int.parse(id)},
    );
    return _seriesFromJson(data['manga'] as Map<String, dynamic>);
  }

  @override
  Future<List<Book>> listBooks(String seriesId) async {
    final data = await _gql(
      'query(\$id: Int!) { manga(id: \$id) { chapters { nodes { id name chapterNumber pageCount lastPageRead isRead mangaId sourceOrder } } } }',
      {'id': int.parse(seriesId)},
    );
    final nodes = data['manga']['chapters']['nodes'] as List;
    final books = nodes.map((e) => _bookFromJson(e)).toList();
    books.sort((a, b) =>
        (double.tryParse(a.number) ?? 0).compareTo(double.tryParse(b.number) ?? 0));
    return books;
  }

  Book _bookFromJson(Map<String, dynamic> e) {
    final id = '${e['id']}';
    final mangaId = '${e['mangaId']}';
    _chapterMangaId[id] = mangaId;
    final sourceOrder = e['sourceOrder'] as int?;
    if (sourceOrder != null) _chapterSourceOrder[id] = sourceOrder;
    final pages = e['pageCount'] as int? ?? -1;
    final lastPageRead = e['lastPageRead'] as int? ?? 0;
    return Book(
      id: id,
      seriesId: mangaId,
      title: e['name'] as String? ?? 'Chapter ${e['chapterNumber'] ?? ''}',
      number: '${e['chapterNumber'] ?? ''}',
      pageCount: pages < 0 ? 0 : pages,
      readProgressPage: lastPageRead == 0 ? null : lastPageRead,
      completed: e['isRead'] as bool? ?? false,
      thumbnailUrl: thumbnailUrlForSeries(mangaId),
    );
  }

  @override
  Future<Book> getBook(String id) async {
    final data = await _gql(
      'query(\$id: Int!) { chapter(id: \$id) { id name chapterNumber pageCount lastPageRead isRead mangaId sourceOrder } }',
      {'id': int.parse(id)},
    );
    final chapter = data['chapter'] as Map<String, dynamic>;
    // Suwayomi reports pageCount -1 until it has actually fetched this
    // chapter's page list from the source (a separate step from fetching
    // the chapter *list* itself, which is all a library-add/sync does).
    // Without this, the reader would build a 0-page view and show nothing.
    if ((chapter['pageCount'] as int? ?? -1) < 0) {
      await _ensureFetched(id);
      final refreshed = await _gql(
        'query(\$id: Int!) { chapter(id: \$id) { id name chapterNumber pageCount lastPageRead isRead mangaId sourceOrder } }',
        {'id': int.parse(id)},
      );
      return _bookFromJson(refreshed['chapter'] as Map<String, dynamic>);
    }
    return _bookFromJson(chapter);
  }

  Future<String> _mangaIdFor(String bookId) async {
    final cached = _chapterMangaId[bookId];
    if (cached != null) return cached;
    final book = await getBook(bookId);
    return book.seriesId;
  }

  Future<int> _sourceOrderFor(String bookId) async {
    final cached = _chapterSourceOrder[bookId];
    if (cached != null) return cached;
    await getBook(bookId); // populates _chapterSourceOrder as a side effect
    final refreshed = _chapterSourceOrder[bookId];
    if (refreshed != null) return refreshed;
    throw StateError('Suwayomi chapter $bookId has no sourceOrder');
  }

  Future<void> _ensureFetched(String bookId) async {
    if (_fetchedChapters.contains(bookId)) return;
    await _gql(
      'mutation(\$id: Int!) { fetchChapterPages(input: {chapterId: \$id}) { chapter { id } } }',
      {'id': int.parse(bookId)},
    );
    _fetchedChapters.add(bookId);
  }

  @override
  Future<Uri> pageUri(String bookId, int pageIndex) async {
    final mangaId = await _mangaIdFor(bookId);
    final sourceOrder = await _sourceOrderFor(bookId);
    await _ensureFetched(bookId);
    return Uri.parse(
        '${config.baseUrl}/api/v1/manga/$mangaId/chapter/$sourceOrder/page/$pageIndex');
  }

  @override
  Future<Uint8List> fetchPage(String bookId, int pageIndex) async {
    final mangaId = await _mangaIdFor(bookId);
    final sourceOrder = await _sourceOrderFor(bookId);
    await _ensureFetched(bookId);
    final res = await _dio.get<List<int>>(
      '/api/v1/manga/$mangaId/chapter/$sourceOrder/page/$pageIndex',
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
    await _gql(
      'mutation(\$id: Int!, \$page: Int!, \$read: Boolean!) { '
      'updateChapter(input: {id: \$id, patch: {lastPageRead: \$page, isRead: \$read}}) { chapter { id } } }',
      {'id': int.parse(bookId), 'page': page, 'read': completed},
    );
  }

  @override
  Future<List<Series>> continueReading() async {
    final data = await _gql(
      '{ mangas(condition: {inLibrary: true}) { nodes { $_mangaFields } } }',
    );
    final nodes = data['mangas']['nodes'] as List;
    return nodes
        .map((e) => _seriesFromJson(e))
        .where((s) => s.booksReadCount > 0 && !s.isFullyRead)
        .take(20)
        .toList();
  }

  @override
  Future<List<Book>> recentlyAdded() async {
    final data = await _gql(
      '{ chapters(order: [{by: FETCHED_AT, byType: DESC}], first: 20) { '
      'nodes { id name chapterNumber pageCount lastPageRead isRead mangaId sourceOrder } } }',
    );
    final nodes = data['chapters']['nodes'] as List;
    return nodes.map((e) => _bookFromJson(e)).toList();
  }

  @override
  Future<List<Collection>> listCollections() async => const [];

  @override
  Future<List<ReadList>> listReadLists() async => const [];

  @override
  String thumbnailUrlForSeries(String seriesId) =>
      '${config.baseUrl}/api/v1/manga/$seriesId/thumbnail';

  @override
  String thumbnailUrlForBook(String bookId) =>
      thumbnailUrlForSeries(_chapterMangaId[bookId] ?? '');

  @override
  Map<String, String> get imageHeaders => const {};

  // ---------------------------------------------------------------------
  // Suwayomi-specific extensions used by the backup import flow (6f). Not
  // part of the generic ReaderBackend contract - only meaningful when the
  // active backend actually is a SuwayomiBackend, since "search an external
  // source and add it to the library" has no equivalent on Komga/Kavita.
  // ---------------------------------------------------------------------

  /// Every source Suwayomi has installed, for mapping a Paperback source to
  /// its Suwayomi equivalent.
  Future<List<({String id, String name, String lang})>> listInstalledSources() async {
    final data = await _gql('{ sources { nodes { id name lang } } }');
    final nodes = data['sources']['nodes'] as List;
    return nodes
        .map((e) => (
              id: '${e['id']}',
              name: e['name'] as String? ?? '',
              lang: e['lang'] as String? ?? '',
            ))
        .toList();
  }

  /// Searches one source's catalog directly (not the local library) - this
  /// is what lets backup import find a title's Suwayomi equivalent before
  /// it's ever been added.
  Future<List<({int id, String title})>> searchSourceCatalog(
      String sourceId, String query) async {
    final data = await _gql(
      'mutation(\$source: LongString!, \$query: String!) { '
      'fetchSourceManga(input: {source: \$source, type: SEARCH, query: \$query, page: 1, filters: []}) { '
      'mangas { id title } } }',
      {'source': sourceId, 'query': query},
    );
    final mangas = data['fetchSourceManga']['mangas'] as List;
    return mangas
        .map((e) => (id: e['id'] as int, title: e['title'] as String? ?? ''))
        .toList();
  }

  /// Returns the id of an existing category named [name], or creates one.
  Future<int> ensureCategory(String name) async {
    final data = await _gql('{ categories { nodes { id name } } }');
    final nodes = data['categories']['nodes'] as List;
    for (final n in nodes) {
      if (n['name'] == name) return n['id'] as int;
    }
    final created = await _gql(
      'mutation(\$name: String!) { createCategory(input: {name: \$name}) { category { id } } }',
      {'name': name},
    );
    return created['createCategory']['category']['id'] as int;
  }

  /// Adds a manga (by its Suwayomi id, from [searchSourceCatalog]) to the
  /// library and assigns it to [categoryIds].
  Future<void> addToLibraryWithCategories(int mangaId, List<int> categoryIds) async {
    await _gql(
      'mutation(\$id: Int!) { updateManga(input: {id: \$id, patch: {inLibrary: true}}) { manga { id } } }',
      {'id': mangaId},
    );
    if (categoryIds.isEmpty) return;
    await _gql(
      'mutation(\$id: Int!, \$cats: [Int!]!) { '
      'updateMangaCategories(input: {id: \$id, patch: {addToCategories: \$cats}}) { manga { id } } }',
      {'id': mangaId, 'cats': categoryIds},
    );
  }

  /// Fetches the real chapter list for [mangaId] from its source (not the
  /// local cache) and returns id-by-chapter-number, so a caller can map
  /// Paperback's own chapter numbers onto Suwayomi's chapter ids.
  Future<Map<double, int>> fetchChapterIdsByNumber(int mangaId) async {
    await _gql(
      'mutation(\$id: Int!) { fetchMangaAndChapters(input: {id: \$id, fetchManga: false, fetchChapters: true}) { manga { id } } }',
      {'id': mangaId},
    );
    final data = await _gql(
      'query(\$id: Int!) { manga(id: \$id) { chapters { nodes { id chapterNumber } } } }',
      {'id': mangaId},
    );
    final nodes = data['manga']['chapters']['nodes'] as List;
    final byNumber = <double, int>{};
    for (final n in nodes) {
      final chapNum = (n['chapterNumber'] as num).toDouble();
      byNumber[chapNum] = n['id'] as int;
    }
    return byNumber;
  }

  /// Marks a batch of chapters read, chunked to keep individual mutations
  /// small.
  Future<void> markChaptersRead(List<int> chapterIds) async {
    for (var i = 0; i < chapterIds.length; i += 200) {
      final batch = chapterIds.skip(i).take(200).toList();
      await _gql(
        'mutation(\$ids: [Int!]!) { updateChapters(input: {ids: \$ids, patch: {isRead: true}}) { chapters { id } } }',
        {'ids': batch},
      );
    }
  }
}
