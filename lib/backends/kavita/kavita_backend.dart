import 'dart:typed_data';

import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';

/// Stub - real implementation lands in Phase 3.
///
/// Exists now so the server-type selector and settings UI can offer
/// "Kavita" as a choice without the app crashing; every method throws
/// [BackendNotImplemented] until Phase 3 fills this in.
class KavitaBackend implements ReaderBackend {
  @override
  final ServerConfig config;

  KavitaBackend({required this.config, required String password});

  Never _unimplemented(String feature) =>
      throw BackendNotImplemented(feature);

  @override
  Future<void> authenticate() => _unimplemented('Kavita authenticate()');

  @override
  Future<List<Library>> listLibraries() => _unimplemented('Kavita libraries');

  @override
  Future<PagedResult<Series>> listSeries({
    String? libraryId,
    int page = 0,
    int size = 20,
    SeriesSort sort = SeriesSort.title,
    SortDirection direction = SortDirection.asc,
    bool unreadOnly = false,
    String? search,
  }) =>
      _unimplemented('Kavita listSeries');

  @override
  Future<Series> getSeries(String id) => _unimplemented('Kavita getSeries');

  @override
  Future<List<Book>> listBooks(String seriesId) =>
      _unimplemented('Kavita listBooks');

  @override
  Future<Book> getBook(String id) => _unimplemented('Kavita getBook');

  @override
  Future<Uri> pageUri(String bookId, int pageIndex) =>
      _unimplemented('Kavita pageUri');

  @override
  Future<Uint8List> fetchPage(String bookId, int pageIndex) =>
      _unimplemented('Kavita fetchPage');

  @override
  Future<void> updateProgress(String bookId,
          {required int page, bool completed = false}) =>
      _unimplemented('Kavita updateProgress');

  @override
  Future<List<Series>> continueReading() =>
      _unimplemented('Kavita continueReading');

  @override
  Future<List<Book>> recentlyAdded() => _unimplemented('Kavita recentlyAdded');

  @override
  Future<List<Collection>> listCollections() =>
      _unimplemented('Kavita listCollections');

  @override
  Future<List<ReadList>> listReadLists() =>
      _unimplemented('Kavita listReadLists');

  @override
  String thumbnailUrlForSeries(String seriesId) => '';

  @override
  String thumbnailUrlForBook(String bookId) => '';

  @override
  Map<String, String> get imageHeaders => const {};
}
