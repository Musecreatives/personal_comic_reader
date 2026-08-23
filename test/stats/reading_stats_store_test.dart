import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:shaddai_reader/core/stats/reading_stats_store.dart';

void main() {
  setUp(() async => await setUpTestHive());
  tearDown(() async => await tearDownTestHive());

  test('is enabled by default', () async {
    final store = ReadingStatsStore();
    await store.init();

    expect(store.enabled, true);
  });

  test('recordPages() and recordSeconds() accumulate for the given day',
      () async {
    final store = ReadingStatsStore();
    await store.init();
    final day = DateTime(2026, 3, 5);

    await store.recordPages(3, date: day);
    await store.recordPages(2, date: day);
    await store.recordSeconds(60, date: day);
    await store.recordSeconds(30, date: day);

    final stat = store.lastDays(1).last;
    // lastDays(1) anchors on "today", not our fixed date, so read totals
    // directly instead.
    expect(store.totalPages, 5);
    expect(store.totalSeconds, 90);
    expect(stat, isNotNull); // sanity: lastDays didn't throw
  });

  test('disabling stats makes record calls a no-op', () async {
    final store = ReadingStatsStore();
    await store.init();
    await store.setEnabled(false);

    await store.recordPages(10);
    await store.recordSeconds(100);

    expect(store.totalPages, 0);
    expect(store.totalSeconds, 0);
  });

  test('lastDays(n) returns n days ending today, oldest first', () async {
    final store = ReadingStatsStore();
    await store.init();
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));

    await store.recordPages(4, date: today);
    await store.recordPages(7, date: yesterday);

    final days = store.lastDays(3);

    expect(days, hasLength(3));
    expect(days.last.pages, 4); // today is last (oldest-first order)
    expect(days[1].pages, 7); // yesterday is second-to-last
    expect(days.first.pages, 0); // two days ago: nothing recorded
  });

  test('currentStreak counts consecutive days with activity, today '
      'not required to have any yet', () async {
    final store = ReadingStatsStore();
    await store.init();
    final today = DateTime.now();

    await store.recordPages(1, date: today.subtract(const Duration(days: 1)));
    await store.recordPages(1, date: today.subtract(const Duration(days: 2)));
    await store.recordPages(1, date: today.subtract(const Duration(days: 3)));
    // Nothing recorded for today yet, and nothing for day 4 - streak
    // should still count the 3 consecutive prior days.

    expect(store.currentStreak, 3);
  });

  test('currentStreak is 0 when there is a gap before today', () async {
    final store = ReadingStatsStore();
    await store.init();
    final today = DateTime.now();

    // Skip yesterday entirely, but read three days ago.
    await store.recordPages(1, date: today.subtract(const Duration(days: 3)));

    expect(store.currentStreak, 0);
  });

  test('currentStreak includes today once today has activity', () async {
    final store = ReadingStatsStore();
    await store.init();
    final today = DateTime.now();

    await store.recordPages(1, date: today);
    await store.recordPages(1, date: today.subtract(const Duration(days: 1)));

    expect(store.currentStreak, 2);
  });
}
