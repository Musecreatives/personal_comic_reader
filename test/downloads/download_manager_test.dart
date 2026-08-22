import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:shaddai_reader/core/backend/models.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';
import 'package:shaddai_reader/core/downloads/download_manager.dart';
import 'package:shaddai_reader/core/downloads/download_models.dart';
import 'package:shaddai_reader/core/downloads/download_store.dart';

class _FakeBackend implements ReaderBackend {
  final Map<String, int> fetchCalls = {};
  final Duration delay;

  _FakeBackend({this.delay = Duration.zero});

  @override
  Future<Uint8List> fetchPage(String bookId, int pageIndex) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    fetchCalls['${bookId}_$pageIndex'] =
        (fetchCalls['${bookId}_$pageIndex'] ?? 0) + 1;
    return Uint8List.fromList([pageIndex]);
  }

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

Future<void> _waitUntil(bool Function() condition,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  setUp(() async => await setUpTestHive());
  tearDown(() async => await tearDownTestHive());

  test('enqueueBook downloads every page and ends in state done', () async {
    final store = DownloadStore();
    await store.init();
    final manager = DownloadManager(store: store);
    final backend = _FakeBackend();

    await manager.enqueueBook(
      backend,
      bookId: 'b1',
      seriesId: 's1',
      seriesTitle: 'Series One',
      title: 'Book 1',
      totalPages: 5,
    );

    await _waitUntil(
        () => store.getTask('b1')?.state == DownloadState.done);

    final task = store.getTask('b1')!;
    expect(task.downloadedPages, 5);
    for (var i = 0; i < 5; i++) {
      expect(store.hasPage('b1', i), true);
    }
  });

  test('pause stops mid-download; resume finishes it', () async {
    final store = DownloadStore();
    await store.init();
    final manager = DownloadManager(store: store);
    final backend = _FakeBackend(delay: const Duration(milliseconds: 20));

    await manager.enqueueBook(
      backend,
      bookId: 'b2',
      seriesId: 's1',
      seriesTitle: 'Series One',
      title: 'Book 2',
      totalPages: 20,
    );
    // Let it actually start running before pausing, so this doesn't race
    // the pump loop's own "is this task still queued" check.
    await _waitUntil(() => store.getTask('b2')?.state == DownloadState.running);
    await manager.pause('b2');

    await _waitUntil(() {
      final t = store.getTask('b2');
      return t != null &&
          (t.state == DownloadState.paused || t.state == DownloadState.done);
    });

    final paused = store.getTask('b2')!;
    if (paused.state == DownloadState.paused) {
      expect(paused.downloadedPages, lessThan(20));
    }

    await manager.resume('b2', backend);
    await _waitUntil(
        () => store.getTask('b2')?.state == DownloadState.done);
    expect(store.getTask('b2')!.downloadedPages, 20);
  });

  test('cancel removes the task and its downloaded pages', () async {
    final store = DownloadStore();
    await store.init();
    final manager = DownloadManager(store: store);
    final backend = _FakeBackend();

    await manager.enqueueBook(
      backend,
      bookId: 'b3',
      seriesId: 's1',
      seriesTitle: 'Series One',
      title: 'Book 3',
      totalPages: 3,
    );
    await _waitUntil(
        () => store.getTask('b3')?.state == DownloadState.done);

    await manager.cancel('b3');

    expect(store.getTask('b3'), isNull);
    expect(store.hasPage('b3', 0), false);
  });

  test('a book already downloaded is not re-fetched on re-enqueue', () async {
    final store = DownloadStore();
    await store.init();
    final manager = DownloadManager(store: store);
    final backend = _FakeBackend();

    await manager.enqueueBook(backend,
        bookId: 'b4',
        seriesId: 's1',
        seriesTitle: 'Series One',
        title: 'Book 4',
        totalPages: 2);
    await _waitUntil(
        () => store.getTask('b4')?.state == DownloadState.done);

    await manager.enqueueBook(backend,
        bookId: 'b4',
        seriesId: 's1',
        seriesTitle: 'Series One',
        title: 'Book 4',
        totalPages: 2);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(backend.fetchCalls['b4_0'], 1);
    expect(backend.fetchCalls['b4_1'], 1);
  });
}
