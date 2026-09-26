import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:shaddai_reader/app/providers.dart';
import 'package:shaddai_reader/core/history/history_entry.dart';
import 'package:shaddai_reader/core/history/history_store.dart';
import 'package:shaddai_reader/core/history/stopped_series_store.dart';

void main() {
  setUp(() async => await setUpTestHive());
  tearDown(() async => await tearDownTestHive());

  HistoryEntry entry(String book, {String? server, required int hour}) =>
      HistoryEntry(
        serverId: server,
        bookId: book,
        seriesId: 'series-$book',
        bookTitle: 'Chapter $book',
        bookNumber: book,
        pageCount: 20,
        lastPage: 3,
        completed: false,
        timestamp: DateTime.utc(2026, 9, 23, hour),
      );

  late StoppedSeriesStore stopped;

  Future<ProviderContainer> containerWith(
      List<HistoryEntry> entries, String? activeId) async {
    final store = HistoryStore();
    await store.init();
    for (final e in entries) {
      await store.record(e);
    }
    stopped = StoppedSeriesStore();
    await stopped.init();
    return ProviderContainer(overrides: [
      historyStoreProvider.overrideWithValue(store),
      stoppedSeriesStoreProvider.overrideWithValue(stopped),
      activeServerIdProvider.overrideWith((ref) => activeId),
    ]);
  }

  test('a stopped series is hidden until it is read again', () async {
    final c = await containerWith([
      entry('1', server: 'a', hour: 1),
      entry('2', server: 'a', hour: 5),
    ], 'a');

    // Stop series-2 after its only read: gone from the list.
    await stopped.stop('a|series-2');
    c.read(stoppedRevisionProvider.notifier).state++;
    expect(c.read(recentReadingProvider).map((e) => e.bookId), ['1']);

    // Resuming brings it back.
    await stopped.resume('a|series-2');
    c.read(stoppedRevisionProvider.notifier).state++;
    expect(c.read(recentReadingProvider).map((e) => e.bookId), ['2', '1']);
  });

  test('isStopped: a read after the stop revives the series', () async {
    await containerWith([], 'a');
    await stopped.stop('a|x');
    final before = DateTime.now().toUtc().subtract(const Duration(hours: 1));
    final after = DateTime.now().toUtc().add(const Duration(hours: 1));

    expect(stopped.isStopped('a|x'), isTrue);
    expect(stopped.isStopped('a|x', lastReadAt: before), isTrue);
    expect(stopped.isStopped('a|x', lastReadAt: after), isFalse);
    expect(stopped.isStopped('a|other'), isFalse);
  });

  test('lists reads from every server, newest first', () async {
    final c = await containerWith([
      entry('1', server: 'a', hour: 1),
      entry('2', server: 'b', hour: 5),
      entry('3', server: 'a', hour: 9),
    ], 'a');

    expect(c.read(recentReadingProvider).map((e) => e.bookId), ['3', '2', '1']);
  });

  test('entries from before servers were tracked are included too',
      () async {
    final c = await containerWith([
      entry('old', server: null, hour: 1),
      entry('other', server: 'b', hour: 2),
    ], 'a');

    expect(c.read(recentReadingProvider).map((e) => e.bookId), ['other', 'old']);
  });
}
