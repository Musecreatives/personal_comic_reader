import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shaddai_reader/core/comicvine/comicvine_client.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/comicvine/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  late DioAdapter adapter;
  late ComicVineClient client;

  setUp(() {
    final dio = Dio(BaseOptions(baseUrl: ComicVineClient.baseUrl));
    adapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
    dio.httpClientAdapter = adapter;
    client = ComicVineClient(apiKey: 'secret', dio: dio);
  });

  test(
    'search parses volumes, tolerating missing publisher/image/year',
    () async {
      adapter.onGet(
        '/search/',
        (server) => server.reply(200, _fixture('search_volumes')),
      );

      final results = await client.searchVolumes('Black Panther');

      expect(results, hasLength(2));
      expect(results[0].id, 106705);
      expect(results[0].name, 'Black Panther');
      expect(results[0].startYear, '2018');
      expect(results[0].publisher, 'Marvel');
      expect(results[0].issueCount, 25);
      expect(results[0].thumbUrl, endsWith('6238341-01.jpg'));
      expect(results[1].publisher, isNull);
      expect(results[1].thumbUrl, isNull);
      expect(results[1].startYear, isNull);
    },
  );

  test(
    'volume detail strips HTML and takes credits from the first issue',
    () async {
      adapter
        ..onGet(
          '/volume/4050-106705/',
          (server) => server.reply(200, _fixture('volume')),
        )
        ..onGet(
          '/issue/4000-659431/',
          (server) => server.reply(200, _fixture('issue')),
        );

      final v = await client.volume(106705);

      expect(
        v.summary,
        "T'Challa takes the fight to the Intergalactic Empire of Wakanda. "
        'Written by Ta-Nehisi Coates & friends.',
      );
      expect(v.publisher, 'Marvel');
      expect(v.startYear, '2018');
      expect(v.writer, 'Ta-Nehisi Coates');
      expect(v.artist, 'Someone Else'); // penciler beats "artist, colorist"
    },
  );

  test('volume detail survives the credits request failing', () async {
    adapter
      ..onGet(
        '/volume/4050-106705/',
        (server) => server.reply(200, _fixture('volume')),
      )
      ..onGet('/issue/4000-659431/', (server) => server.reply(420, ''));

    final v = await client.volume(106705);
    expect(v.publisher, 'Marvel');
    expect(v.writer, isNull);
  });

  test('HTTP 420 is reported as the rate limit', () async {
    adapter.onGet('/search/', (server) => server.reply(420, ''));
    await expectLater(
      client.searchVolumes('x'),
      throwsA(
        isA<ComicVineException>().having(
          (e) => e.message,
          'message',
          contains('rate limit'),
        ),
      ),
    );
  });

  test('a bad key (status_code 100 with HTTP 200) is reported as such', () {
    expect(
      () => ComicVineClient.parseResults({
        'error': 'Invalid API Key',
        'status_code': 100,
        'results': [],
      }),
      throwsA(
        isA<ComicVineException>().having(
          (e) => e.message,
          'message',
          contains('API key'),
        ),
      ),
    );
  });

  test('no results is an empty list, not an error', () async {
    adapter.onGet(
      '/search/',
      (server) =>
          server.reply(200, {'error': 'OK', 'status_code': 1, 'results': []}),
    );
    expect(await client.searchVolumes('zzzz'), isEmpty);
  });

  test('creditsFromPersonCredits falls back to inker, then cover', () {
    expect(
      creditsFromPersonCredits([
        {'name': 'C', 'role': 'cover'},
        {'name': 'I', 'role': 'inker'},
      ]).artist,
      'I',
    );
    expect(
      creditsFromPersonCredits([
        {'name': 'C', 'role': 'cover'},
      ]),
      (writer: null, artist: 'C'),
    );
  });
}
