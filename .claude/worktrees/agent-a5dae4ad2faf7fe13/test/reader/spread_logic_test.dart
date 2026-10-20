import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/core/reader/reader_settings.dart';
import 'package:shaddai_reader/core/reader/spread_logic.dart';

void main() {
  group('buildSpreads', () {
    test('pairs pages with cover alone', () {
      final spreads = buildSpreads(pageCount: 5, coverAlone: true);
      expect(spreads, [
        [0],
        [1, 2],
        [3, 4],
      ]);
    });

    test('pairs pages with no cover alone', () {
      final spreads = buildSpreads(pageCount: 4, coverAlone: false);
      expect(spreads, [
        [0, 1],
        [2, 3],
      ]);
    });

    test('leaves a trailing single page when the count is odd', () {
      final spreads = buildSpreads(pageCount: 4, coverAlone: true);
      expect(spreads, [
        [0],
        [1, 2],
        [3],
      ]);
    });

    test('offset shifts pairing start by extra singles', () {
      final spreads = buildSpreads(pageCount: 6, coverAlone: true, offset: 1);
      expect(spreads, [
        [0],
        [1],
        [2, 3],
        [4, 5],
      ]);
    });

    test('landscape pages are never paired', () {
      final spreads = buildSpreads(
        pageCount: 5,
        coverAlone: true,
        isLandscape: (i) => i == 2,
      );
      expect(spreads, [
        [0],
        [1],
        [2],
        [3, 4],
      ]);
    });

    test('empty book yields no spreads', () {
      expect(buildSpreads(pageCount: 0), isEmpty);
    });
  });

  group('spreadDisplayOrder', () {
    test('ltr keeps reading order', () {
      expect(spreadDisplayOrder([2, 3], ReadingDirection.ltr), [2, 3]);
    });

    test('rtl mirrors the pair for screen display', () {
      expect(spreadDisplayOrder([2, 3], ReadingDirection.rtl), [3, 2]);
    });

    test('single-page spreads are unaffected by direction', () {
      expect(spreadDisplayOrder([0], ReadingDirection.rtl), [0]);
    });
  });

  group('display position mapping', () {
    test('ltr: display position equals page index', () {
      expect(displayPositionForPage(3, 10, ReadingDirection.ltr), 3);
      expect(pageForDisplayPosition(3, 10, ReadingDirection.ltr), 3);
    });

    test('rtl: page 0 sits at the right edge of the slider', () {
      expect(displayPositionForPage(0, 10, ReadingDirection.rtl), 9);
      expect(displayPositionForPage(9, 10, ReadingDirection.rtl), 0);
    });

    test('rtl mapping is its own inverse', () {
      for (var page = 0; page < 10; page++) {
        final pos = displayPositionForPage(page, 10, ReadingDirection.rtl);
        expect(pageForDisplayPosition(pos, 10, ReadingDirection.rtl), page);
      }
    });
  });
}
