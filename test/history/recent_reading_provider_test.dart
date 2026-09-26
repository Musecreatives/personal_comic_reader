import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:shaddai_reader/app/providers.dart';
import 'package:shaddai_reader/core/history/history_entry.dart';
import 'package:shaddai_reader/core/history/history_store.dart';

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

  Future<ProviderContainer> containerWith(
      List<HistoryEntry> entries, String? activeId) async {
    final store = HistoryStore();
    await store.init();
    for (final e in entries) {
      await store.record(e);
    }
    return ProviderContainer(overrides: [
      historyStoreProvider.overrideWithValue(store),
      activeServerIdProvider.overrideWith((ref) => activeId),
    ]);
  }

  test("lists only the active server's reads, newest first", () async {
    final c = await containerWith([
      entry('1', server: 'a', hour: 1),
      entry('2', server: 'b', hour: 5),
      entry('3', server: 'a', hour: 9),
    ], 'a');

    expect(c.read(recentReadingProvider).map((e) => e.bookId), ['3', '1']);
  });

  test('entries from before servers were tracked count as the active server',
      () async {
    final c = await containerWith([
      entry('old', server: null, hour: 1),
      entry('other', server: 'b', hour: 2),
    ], 'a');

    expect(c.read(recentReadingProvider).map((e) => e.bookId), ['old']);
  });
}
