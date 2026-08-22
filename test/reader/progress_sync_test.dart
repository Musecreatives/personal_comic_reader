import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:shaddai_reader/core/backend/models.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';
import 'package:shaddai_reader/core/reader/progress_sync.dart';

class _FakeBackend implements ReaderBackend {
  final List<Map<String, dynamic>> calls = [];
  bool shouldFail = false;

  @override
  Future<void> updateProgress(
    String bookId, {
    required int page,
    bool completed = false,
  }) async {
    if (shouldFail) throw Exception('network down');
    calls.add({'bookId': bookId, 'page': page, 'completed': completed});
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
  Future<Uint8List> fetchPage(String bookId, int pageIndex) =>
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

  test('scheduleUpdate sends once after the debounce window', () async {
    final sync = ProgressSync();
    await sync.init();
    final backend = _FakeBackend();

    sync.scheduleUpdate(backend, 'book1', page: 5);
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    expect(backend.calls, [
      {'bookId': 'book1', 'page': 5, 'completed': false}
    ]);
  });

  test('rapid updates collapse into a single send with the latest value',
      () async {
    final sync = ProgressSync();
    await sync.init();
    final backend = _FakeBackend();

    sync.scheduleUpdate(backend, 'book1', page: 1);
    sync.scheduleUpdate(backend, 'book1', page: 2);
    sync.scheduleUpdate(backend, 'book1', page: 3);
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    expect(backend.calls.length, 1);
    expect(backend.calls.first['page'], 3);
  });

  test('a failed send is queued and retried on the next flush', () async {
    final sync = ProgressSync();
    await sync.init();
    final backend = _FakeBackend()..shouldFail = true;

    await sync.sendNow(backend, 'book1', page: 7, completed: true);
    expect(backend.calls, isEmpty);

    backend.shouldFail = false;
    await sync.flushQueue(backend);

    expect(backend.calls, [
      {'bookId': 'book1', 'page': 7, 'completed': true}
    ]);
  });

  test('flushQueue is a no-op once the queue is empty', () async {
    final sync = ProgressSync();
    await sync.init();
    final backend = _FakeBackend();

    await sync.flushQueue(backend);

    expect(backend.calls, isEmpty);
  });
}
