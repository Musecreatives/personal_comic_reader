import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/core/share/page_share.dart';

void main() {
  group('sourceUrl', () {
    test('joins a relative path onto the source address', () {
      expect(
        sourceUrl('https://asurascans.com/', '/series/x/chapter/45'),
        'https://asurascans.com/series/x/chapter/45',
      );
    });

    test('keeps a path that is already a full address', () {
      expect(
        sourceUrl('https://www.mangabats.com', 'https://www.mangabats.com/manga/x/chapter-185'),
        'https://www.mangabats.com/manga/x/chapter-185',
      );
    });

    test('no path or no base for a relative path gives no link', () {
      expect(sourceUrl('https://a.com', null), isNull);
      expect(sourceUrl(null, '/series/x'), isNull);
    });
  });

  test('caption names the title, chapter, source, pages and links', () {
    expect(
      shareCaption(
        title: 'Chronicles Of The Demon Faction',
        chapter: 'Ch. 190',
        source: 'Asura Scans (EN)',
        pages: [8, 7],
        sourceLink: 'https://asurascans.com/series/x/chapter/190',
        appLink: appLinkForSeries('1'),
      ),
      'Chronicles Of The Demon Faction\n'
      'Ch. 190 · Asura Scans (EN) · pp. 8, 9\n'
      'Read it: https://asurascans.com/series/x/chapter/190\n'
      'In Shaddai Reader: https://reader.shaddaicommunications.com/#/series/1',
    );
  });

  group('stripCuts', () {
    test('a normal page goes whole', () {
      expect(stripCuts(1000, 1500), [(0, 1500)]);
      expect(stripCuts(800, 2400), [(0, 2400)]);
    });

    test('a webtoon strip is cut into even phone-shaped pieces', () {
      final cuts = stripCuts(720, 20000);
      expect(cuts.length, 14); // 20000 / 1440, rounded up
      expect(cuts.first.$1, 0);
      expect(cuts.last.$2, 20000);
      for (var k = 1; k < cuts.length; k++) {
        expect(cuts[k].$1, cuts[k - 1].$2); // no gaps, no overlap
      }
      for (final (top, bottom) in cuts) {
        expect(bottom - top, lessThanOrEqualTo(1440));
      }
    });
  });

  test('caption leaves out what it does not know', () {
    expect(
      shareCaption(title: 'Saga', chapter: 'Ch. 3', pages: [0]),
      'Saga\nCh. 3 · p. 1',
    );
  });
}
