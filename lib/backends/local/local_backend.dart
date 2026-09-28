import 'dart:typed_data';

import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
import 'local_library_store.dart';

/// The library id every "series" is filed under - there's only one, since a
/// manual import has no server-side folder structure to mirror.
const localLibraryId = 'local';

/// [ReaderBackend] for manually-imported comics/manga. Every book is fully
/// on-device already (imported and unzipped up front), so [fetchPage] just
/// reads bytes back out of [LocalLibraryStore] - there's nothing to stream.
class LocalBackend implements ReaderBackend {
  @override
  final ServerConfig config;
  final LocalLibraryStore store;

  const LocalBackend({required this.config, required this.store});

  Series _toSeries(LocalSeriesRecord s) {
    final books = store.listBooksForSeries(s.id);
    final read = books.where((b) => b.completed).length;
    return Series(
      id: s.id,
      libraryId: localLibraryId,
      title: s.title,
      booksCount: books.length,
      booksReadCount: read,
      booksUnreadCount: books.length - read,
    );
  }

  Book _toBook(LocalBookRecord b) => Book(
        id: b.id,
        seriesId: b.seriesId,
        title: b.title,
        number: b.number,
        pageCount: b.pageCount,
        readProgressPage: b.readProgressPage,
        completed: b.completed,
      );

  @override
  Future<void> authenticate() async {}

  @override
  Future<List<Library>> listLibraries() async =>
      const [Library(id: localLibraryId, name: 'On This Device')];

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
    var all = store.listSeries().map(_toSeries).toList();
    if (unreadOnly) all = all.where((s) => !s.isFullyRead).toList();
    if (search != null && search.isNotEmpty) {
      final q = search.toLowerCase();
      all = all.where((s) => s.title.toLowerCase().contains(q)).toList();
    }
    if (sort == SeriesSort.title) {
      all.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      if (direction == SortDirection.desc) all = all.reversed.toList();
    }
    // dateAdded/dateUpdated/releaseDate: store.listSeries() already returns
    // newest-imported-first, which is the only "date" this backend tracks.
    final start = (page * size).clamp(0, all.length);
    final end = (start + size).clamp(0, all.length);
    return PagedResult(
      items: all.sublist(start, end),
      page: page,
      size: size,
      totalPages: (all.length / size).ceil().clamp(1, 1 << 30),
      totalElements: all.length,
    );
  }

  @override
  Future<Series> getSeries(String id) async {
    final s = store.getSeries(id);
    if (s == null) throw StateError('No local series with id "$id"');
    return _toSeries(s);
  }

  @override
  Future<List<Book>> listBooks(String seriesId) async =>
      store.listBooksForSeries(seriesId).map(_toBook).toList();

  @override
  Future<Book> getBook(String id) async {
    final b = store.getBook(id);
    if (b == null) throw StateError('No imported book with id "$id"');
    return _toBook(b);
  }

  @override
  Future<Uri> pageUri(String bookId, int pageIndex) =>
      throw const BackendNotImplemented(
          'Local books have no URL - use fetchPage.');

  @override
  Future<Uint8List> fetchPage(String bookId, int pageIndex) async {
    final bytes = await store.getPage(bookId, pageIndex);
    if (bytes == null) {
      throw StateError('Page $pageIndex missing for imported book "$bookId"');
    }
    return bytes;
  }

  @override
  Future<void> updateProgress(
    String bookId, {
    required int page,
    bool completed = false,
  }) async {
    final b = store.getBook(bookId);
    if (b == null) return;
    await store.putBook(b.copyWith(readProgressPage: page, completed: completed));
  }

  @override
  Future<List<Series>> continueReading() async {
    final inProgress = store
        .listAllBooks()
        .where((b) => !b.completed && b.readProgressPage > 0)
        .map((b) => b.seriesId)
        .toSet();
    return inProgress
        .map(store.getSeries)
        .whereType<LocalSeriesRecord>()
        .map(_toSeries)
        .toList();
  }

  @override
  Future<List<Book>> recentlyAdded() async {
    final books = store.listAllBooks()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return books.map(_toBook).toList();
  }

  @override
  Future<List<Collection>> listCollections() async => const [];

  @override
  Future<List<ReadList>> listReadLists() async => const [];

  @override
  String thumbnailUrlForSeries(String seriesId) => '';

  @override
  String thumbnailUrlForBook(String bookId) => '';

  @override
  Map<String, String> get imageHeaders => const {};
}
