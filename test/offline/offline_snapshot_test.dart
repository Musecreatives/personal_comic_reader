import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:shaddai_reader/core/backend/models.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';
import 'package:shaddai_reader/core/offline/offline_snapshot.dart';

/// Answers until [down] is set, then fails like a phone with no network.
class _Backend extends Fake implements ReaderBackend {
  bool down = false;
  bool hang = false;
  int calls = 0;

  @override
  ServerConfig get config => const ServerConfig(
      id: 's1', name: 'S', type: ServerType.suwayomi, baseUrl: 'x', username: 'u');

  Future<T> _answer<T>(T value) async {
    calls++;
    if (hang) return Future.delayed(const Duration(hours: 1), () => value);
    if (down) throw Exception('no network');
    return value;
  }

  @override
  Future<Series> getSeries(String id) => _answer(Series(
      id: id,
      libraryId: 'l',
      title: 'Absolute Regression',
      booksCount: 2,
      booksReadCount: 1,
      booksUnreadCount: 1,
      tags: const ['Action'],
      status: SeriesStatus.ongoing));

  @override
  Future<List<Book>> listBooks(String seriesId) => _answer([
        for (final n in [1, 2])
          Book(
              id: 'b$n',
              seriesId: seriesId,
              title: 'Chapter $n',
              number: '$n',
              pageCount: 20,
              completed: n == 1,
              addedAt: DateTime.utc(2026, 11, n)),
      ]);

  @override
  Future<Book> getBook(String id) => throw Exception('no network');
}

void main() {
  setUp(() async => setUpTestHive());
  tearDown(() async => tearDownTestHive());

  test('a series opened once still opens, and its chapters too, offline',
      () async {
    final snapshot = OfflineSnapshot();
    await snapshot.init();
    final backend = _Backend();
    await snapshot.getSeries(backend, '7');
    await snapshot.listBooks(backend, '7');

    backend.down = true;
    final series = await snapshot.getSeries(backend, '7');
    expect(series.title, 'Absolute Regression');
    expect(series.status, SeriesStatus.ongoing);
    expect(series.tags, ['Action']);
    final books = await snapshot.listBooks(backend, '7');
    expect(books.map((b) => b.id), ['b1', 'b2']);
    expect(books.first.completed, isTrue);
    expect(books.last.addedAt, DateTime.utc(2026, 11, 2));
    // The reader opens a chapter by id, never fetched on its own.
    expect((await snapshot.getBook(backend, 'b2')).title, 'Chapter 2');
  });

  test('with no network the saved copy is used without asking the server',
      () async {
    final snapshot = OfflineSnapshot();
    await snapshot.init();
    final backend = _Backend();
    await snapshot.getSeries(backend, '7');
    backend
      ..calls = 0
      ..hang = true;
    snapshot.offline = true;
    expect((await snapshot.getSeries(backend, '7')).id, '7');
    expect(backend.calls, 0);
  });

  test('a server that stops answering falls back after the wait', () async {
    final snapshot =
        OfflineSnapshot(fallbackAfter: const Duration(milliseconds: 50));
    await snapshot.init();
    final backend = _Backend();
    await snapshot.getSeries(backend, '7');
    backend.hang = true;
    expect((await snapshot.getSeries(backend, '7')).id, '7');
  });

  test('nothing saved: the error still reaches the screen', () async {
    final snapshot = OfflineSnapshot();
    await snapshot.init();
    final backend = _Backend()..down = true;
    expect(snapshot.getSeries(backend, '9'), throwsException);
  });
}
