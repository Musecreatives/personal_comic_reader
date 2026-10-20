import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/core/backend/models.dart';
import 'package:shaddai_reader/core/history/history_entry.dart';
import 'package:shaddai_reader/core/history/history_groups.dart';

HistoryEntry _e(String series, String book, int minutesAgo, {String? server}) =>
    HistoryEntry(
      serverId: server,
      bookId: book,
      seriesId: series,
      bookTitle: book,
      bookNumber: book,
      pageCount: 20,
      lastPage: 5,
      completed: false,
      timestamp: DateTime(2026, 9, 28, 12).subtract(Duration(minutes: minutesAgo)),
    );

Book _b(String id, {bool completed = false}) => Book(
      id: id,
      seriesId: 's',
      title: id,
      number: id,
      pageCount: 20,
      completed: completed,
    );

void main() {
  group('groupHistoryBySeries', () {
    test('groups by series, most recently read series first', () {
      final groups = groupHistoryBySeries([
        _e('a', 'a1', 30),
        _e('b', 'b1', 10),
        _e('a', 'a2', 5),
      ]);
      expect(groups.map((g) => g.seriesId), ['a', 'b']);
      expect(groups.first.entries.map((e) => e.bookId), ['a2', 'a1']);
    });

    test('the same series id on two servers stays separate', () {
      final groups = groupHistoryBySeries([
        _e('1', 'x', 1, server: 'komga'),
        _e('1', 'y', 2, server: 'suwayomi'),
      ]);
      expect(groups, hasLength(2));
    });
  });

  group('newChaptersSince', () {
    final books = [for (var i = 1; i <= 5; i++) _b('c$i')];

    test('chapters after the furthest one read are new', () {
      expect(newChaptersSince(books, ['c2', 'c3']).map((b) => b.id),
          ['c4', 'c5']);
    });

    test('re-reading an early chapter does not flag later read ones', () {
      final withRead = [
        _b('c1'), _b('c2'), _b('c3', completed: true), _b('c4'),
      ];
      expect(newChaptersSince(withRead, ['c1']).map((b) => b.id), ['c4']);
    });

    test('caught up means nothing new', () {
      expect(newChaptersSince(books, ['c5']), isEmpty);
    });

    test('a series with nothing read has no "new" chapters', () {
      expect(newChaptersSince(books, ['not-in-list']), isEmpty);
    });
  });
}
