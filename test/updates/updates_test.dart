import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/core/backend/models.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';
import 'package:shaddai_reader/core/updates/updates.dart';
import 'package:shaddai_reader/features/updates/updates_screen.dart';

Book _ch(String series, String number, DateTime at, {bool read = false, String? id}) => Book(
      id: id ?? '$series-$number',
      seriesId: series,
      title: 'Chapter $number',
      number: number,
      pageCount: 20,
      completed: read,
      addedAt: at,
    );

UpdateChapter _u(String server, Book b) =>
    UpdateChapter(serverId: server, seriesTitle: 'Title ${b.seriesId}', book: b);

class _FakeBackend implements ReaderBackend {
  @override
  ServerConfig get config => const ServerConfig(
      id: 'suwa', name: 'S', type: ServerType.suwayomi, baseUrl: 'http://s', username: '');
  @override
  Map<String, String> get imageHeaders => const {};
  @override
  String thumbnailUrlForSeries(String seriesId) => '';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final mon = DateTime(2026, 10, 26, 9);
  final tue = DateTime(2026, 10, 27, 20);

  test('keeps followed series, one row per series per day, newest first', () {
    final groups = groupUpdates([
      _u('suwa', _ch('a', '160', mon)),
      _u('suwa', _ch('a', '161', mon.add(const Duration(hours: 1)))),
      _u('suwa', _ch('a', '162', tue)),
      _u('komga', _ch('k', '5', mon.add(const Duration(hours: 3)))),
      _u('komga', _ch('stranger', '1', tue)), // not followed
      _u('suwa', Book(id: 'x', seriesId: 'a', title: '', number: '9', pageCount: 1, completed: false)),
    ], follows: (server, series) => series != 'stranger');

    expect([for (final g in groups) '${g.serverId}/${g.seriesId}/${g.chapters.length}'],
        ['suwa/a/1', 'komga/k/1', 'suwa/a/2']);
    expect(chapterRange(groups.last.chapters), 'CH. 160–161');
  });

  test('a tap opens the oldest unread chapter, or the newest when all are read', () {
    final g = groupUpdates([
      _u('s', _ch('a', '3', mon.add(const Duration(hours: 2)))),
      _u('s', _ch('a', '2', mon.add(const Duration(hours: 1)))),
      _u('s', _ch('a', '1', mon, read: true)),
    ], follows: (_, _) => true).single;
    expect(g.next.number, '2');
    expect(g.hasUnread, isTrue);

    final allRead = groupUpdates([
      _u('s', _ch('a', '2', mon.add(const Duration(hours: 1)), read: true)),
      _u('s', _ch('a', '1', mon, read: true)),
    ], follows: (_, _) => true).single;
    expect(allRead.next.number, '2');
    expect(allRead.hasUnread, isFalse);
  });

  test('day labels, chapter ranges and ages', () {
    final now = DateTime(2026, 10, 28, 12);
    expect(dayLabel(DateTime(2026, 10, 28), now), 'TODAY');
    expect(dayLabel(DateTime(2026, 10, 27), now), 'YESTERDAY');
    expect(dayLabel(DateTime(2026, 10, 26), now), 'MON 26 OCT');
    expect(dayLabel(DateTime(2025, 12, 31), now), 'WED 31 DEC 2025');
    expect(chapterRange([_ch('a', '10.5', mon)]), 'CH. 10.5');
    expect(chapterRange([_ch('a', '012', mon), _ch('a', '10', mon)]), 'CH. 10–12');
    expect(agoLabel(now.subtract(const Duration(hours: 2)), now), '2 H AGO');
    expect(agoLabel(now, now), 'JUST NOW');
  });

  for (final size in const [Size(390, 844), Size(1101, 688), Size(688, 1101)]) {
    testWidgets('the Updates screen lays out at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final feed = UpdatesFeed(
        groups: groupUpdates([
          for (var i = 0; i < 12; i++)
            _u('suwa', _ch('s$i', '${100 + i}', now.subtract(Duration(hours: i * 7)))),
        ], follows: (_, _) => true),
        backends: {'suwa': _FakeBackend()},
        lastChecked: now.subtract(const Duration(hours: 2)),
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [updatesProvider.overrideWith((ref) async => feed)],
        child: const MaterialApp(home: UpdatesScreen()),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('LAST CHECKED 2 H AGO'), findsOneWidget);
    });
  }
}
