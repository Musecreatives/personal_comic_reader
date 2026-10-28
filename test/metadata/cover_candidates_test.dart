import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shaddai_reader/backends/suwayomi/suwayomi_backend.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';
import 'package:shaddai_reader/core/metadata/cover_candidates.dart';
import 'package:shaddai_reader/core/network/image_origins.dart';
import 'package:shaddai_reader/features/series/series_actions_sheet.dart';

// Trimmed from real responses (2026-10).
const _anilist = {
  'data': {
    'Page': {
      'media': [
        {
          'title': {'romaji': 'Hwasan Gwihwan', 'english': 'Return of the Mount Hua Sect', 'native': '화산귀환'},
          'synonyms': ['Return of the Blossoming Blade'],
          'startDate': {'year': 2019},
          'status': 'RELEASING',
          'genres': ['Action', 'Comedy'],
          'description': 'Chung Myung, <i>the 13th disciple</i>.<br><br>Reborn.',
          'coverImage': {'extraLarge': 'https://s4.anilist.co/cover/large/bx1.jpg'},
          'bannerImage': 'https://s4.anilist.co/banner/1.jpg',
        },
        {
          'title': {'romaji': 'No Cover'},
          'coverImage': {'extraLarge': null},
        },
      ],
    },
  },
};

const _mangadex = {
  'data': [
    {
      'id': 'abc-123',
      'attributes': {
        'title': {'en': 'Return of the Mount Hua Sect'},
        'altTitles': [
          {'ko': '화산귀환'},
          {'en': 'Return of the Blossoming Blade'},
        ],
        'description': {'en': 'A swordsman returns.'},
        'year': 2019,
        'status': 'completed',
        'tags': [
          {'attributes': {'name': {'en': 'Martial Arts'}, 'group': 'genre'}},
          {'attributes': {'name': {'en': 'Long Strip'}, 'group': 'format'}},
        ],
      },
      'relationships': [
        {'type': 'author', 'attributes': {}},
        {'type': 'cover_art', 'attributes': {'fileName': 'cover.png'}},
      ],
    },
    {'id': 'no-cover', 'attributes': {'title': {'en': 'x'}}, 'relationships': []},
  ],
};

void main() {
  test('AniList: cover, banner, alt titles, plain-text summary, status', () {
    final list = parseAniList(_anilist);
    expect(list, hasLength(1)); // the one without a cover is dropped
    final c = list.single;
    expect(c.title, 'Return of the Mount Hua Sect');
    expect(c.altTitles, containsAll(['Hwasan Gwihwan', '화산귀환', 'Return of the Blossoming Blade']));
    expect(c.coverUrl, 'https://s4.anilist.co/cover/large/bx1.jpg');
    expect(c.bannerUrl, 'https://s4.anilist.co/banner/1.jpg');
    expect(c.description, 'Chung Myung, the 13th disciple. Reborn.');
    expect(c.status, SeriesStatus.ongoing);
    expect(c.year, 2019);
  });

  test('MangaDex: original-size cover URL, genre tags only, status', () {
    final c = parseMangaDex(_mangadex).single;
    expect(c.coverUrl, 'https://uploads.mangadex.org/covers/abc-123/cover.png');
    expect(c.genres, ['Martial Arts']);
    expect(c.status, SeriesStatus.ended);
    expect(c.altTitles, contains('Return of the Blossoming Blade'));
  });

  test('ranking puts an alt-title match above a loose one', () {
    const loose = CoverCandidate(source: 'X', title: 'Mount Hua Chronicles', coverUrl: 'a');
    const exact = CoverCandidate(
        source: 'Y', title: 'Hwasan Gwihwan', altTitles: ['Return of the Blossoming Blade'], coverUrl: 'b');
    final ranked = rankCandidates('Return of the Blossoming Blade!', [loose, exact]);
    expect(ranked.first, same(exact));
    expect(titleScore('Return of the Blossoming Blade', exact), 1);
    expect(titleScore('', exact), 0);
  });

  test('login headers only go to registered servers', () {
    trustImageOrigin('http://100.108.109.63:4567');
    const h = {'Authorization': 'Basic x'};
    expect(imageHeadersFor('http://100.108.109.63:4567/api/v1/manga/1/thumbnail', h), h);
    expect(imageHeadersFor('https://s4.anilist.co/cover.jpg', h), isEmpty);
    expect(imageHeadersFor('http://100.108.109.63:9999/x', h), isEmpty); // other port
    expect(imageHeadersFor('http://100.108.109.63.evil.example:4567/x', h), isEmpty);
    expect(imageHeadersFor('not a url', h), isEmpty);
  });

  group('Suwayomi overrides', () {
    late DioAdapter adapter;
    late SuwayomiBackend backend;
    setUp(() {
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      adapter = DioAdapter(dio: dio);
      dio.httpClientAdapter = adapter;
      backend = SuwayomiBackend(
        config: const ServerConfig(
            id: 's', name: 'S', type: ServerType.suwayomi, baseUrl: 'http://test.local', username: ''),
        password: '',
        dio: dio,
      );
    });

    void reply(List<Map<String, String>> meta) => adapter.onPost(
          '/api/graphql',
          (server) => server.reply(200, {
            'data': {
              'manga': {
                'id': 7,
                'title': 'T',
                'description': 'From the source.',
                'unreadCount': 0,
                'chapters': {'totalCount': 3},
                'meta': meta,
              },
            },
          }),
          data: Matchers.any,
        );

    test('a picked cover, banner and summary win over the source', () async {
      reply([
        {'key': coverMetaKey, 'value': 'https://s4.anilist.co/c.jpg'},
        {'key': bannerMetaKey, 'value': 'https://s4.anilist.co/b.jpg'},
        {'key': detailsMetaKey, 'value': '{"summary":"Picked.","genres":["Action"]}'},
      ]);
      final s = await backend.getSeries('7');
      expect(s.thumbnailUrl, 'https://s4.anilist.co/c.jpg');
      expect(s.bannerUrl, 'https://s4.anilist.co/b.jpg');
      expect(s.summary, 'Picked.');
      expect(s.tags, ['Action']);
      // Other screens that only know the id get the picked cover too.
      expect(backend.thumbnailUrlForSeries('7'), 'https://s4.anilist.co/c.jpg');
    });

    test('without overrides the source cover and summary stay', () async {
      reply(const []);
      final s = await backend.getSeries('7');
      expect(s.thumbnailUrl, 'http://test.local/api/v1/manga/7/thumbnail');
      expect(s.summary, 'From the source.');
      expect(s.bannerUrl, isNull);
    });
  });

  testWidgets('the series menu offers the refresh only when it is passed in',
      (tester) async {
    Future<void> open({required bool owner}) async {
      // A fresh app each time, so the first sheet isn't still covering
      // the button.
      await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => SeriesActionsSheet.show(
              context,
              title: 'T',
              downloadedCount: 0,
              canRemoveFromLibrary: false,
              onStopReading: () async {},
              onDeleteDownloads: () async {},
              onRemoveFromLibrary: () async {},
              onRefreshCover: owner ? () async {} : null,
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    await open(owner: true);
    expect(find.text('Refresh cover & details'), findsOneWidget);
    await open(owner: false);
    expect(find.text('Stop reading'), findsOneWidget); // the menu did open
    expect(find.text('Refresh cover & details'), findsNothing);
  });
}
