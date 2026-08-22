import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hive_test/hive_test.dart';
import 'package:shaddai_reader/core/backend/models.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';
import 'package:shaddai_reader/core/downloads/download_store.dart';
import 'package:shaddai_reader/core/reader/page_cache.dart';

/// A backend that always throws - stands in for "there is no network",
/// so any test that gets bytes back proved they came from somewhere else.
class _OfflineBackend implements ReaderBackend {
  @override
  Future<Uint8List> fetchPage(String bookId, int pageIndex) =>
      throw Exception('offline: no network');

  @override
  ServerConfig get config => throw UnimplementedError();
  @override
  Future<void> authenticate() => throw UnimplementedError();
  @override
  Future<List<Library>> listLibraries() => throw UnimplementedError();
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
      throw UnimplementedError();
  @override
  Future<Series> getSeries(String id) => throw UnimplementedError();
  @override
  Future<List<Book>> listBooks(String seriesId) => throw UnimplementedError();
  @override
  Future<Book> getBook(String id) => throw UnimplementedError();
  @override
  Future<Uri> pageUri(String bookId, int pageIndex) =>
      throw UnimplementedError();
  @override
  Future<void> updateProgress(String bookId,
          {required int page, bool completed = false}) =>
      throw UnimplementedError();
  @override
  Future<List<Series>> continueReading() => throw UnimplementedError();
  @override
  Future<List<Book>> recentlyAdded() => throw UnimplementedError();
  @override
  Future<List<Collection>> listCollections() => throw UnimplementedError();
  @override
  Future<List<ReadList>> listReadLists() => throw UnimplementedError();
  @override
  String thumbnailUrlForSeries(String seriesId) => throw UnimplementedError();
  @override
  String thumbnailUrlForBook(String bookId) => throw UnimplementedError();
  @override
  Map<String, String> get imageHeaders => throw UnimplementedError();
}

void main() {
  setUp(() async => await setUpTestHive());
  tearDown(() async => await tearDownTestHive());

  test('a downloaded page is returned without ever touching the network',
      () async {
    final downloadStore = DownloadStore();
    await downloadStore.init();
    await downloadStore.putPage('book1', 3, Uint8List.fromList([9, 9, 9]));

    final pageCache = PageCache(downloadStore: downloadStore);
    await pageCache.init();

    final bytes = await pageCache.getPage(_OfflineBackend(), 'book1', 3);

    expect(bytes, [9, 9, 9]);
  });

  test('a page with no download falls through to the network and throws',
      () async {
    final downloadStore = DownloadStore();
    await downloadStore.init();

    final pageCache = PageCache(downloadStore: downloadStore);
    await pageCache.init();

    expect(
      () => pageCache.getPage(_OfflineBackend(), 'book1', 0),
      throwsException,
    );
  });

  test(
      'a downloaded page wins even when a different copy is already sitting '
      'in the opportunistic disk cache', () async {
    // Pre-seed PageCache's own disk cache box directly, bypassing the
    // download path, to prove the download-store check really does run
    // first rather than just happening to be the only source of data.
    final opportunisticCacheBox = await Hive.openBox<Uint8List>('page_cache');
    await opportunisticCacheBox.put('book1_0', Uint8List.fromList([7, 7, 7]));

    final downloadStore = DownloadStore();
    await downloadStore.init();
    await downloadStore.putPage('book1', 0, Uint8List.fromList([1, 2, 3]));

    final pageCache = PageCache(downloadStore: downloadStore);
    await pageCache.init();

    final bytes = await pageCache.getPage(_OfflineBackend(), 'book1', 0);

    expect(bytes, [1, 2, 3]);
  });
}
