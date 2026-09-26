import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shaddai_reader/core/kapowarr/kapowarr_client.dart';
import 'package:shaddai_reader/core/kapowarr/kapowarr_config.dart';

void main() {
  test('search results parse loose types and strip HTML from the description', () {
    final r = KapowarrSearchResult.fromJson({
      'comicvine_id': '167340', // sometimes a string
      'title': 'Absolute Batman',
      'year': '2025',
      'volume_number': 1,
      'cover_link': 'https://example.test/c.jpg',
      'description':
          '<p>Collected &amp; <a href="x">editions</a> of the&nbsp;series.</p>',
      'publisher': 'DC Comics',
      'issue_count': '3',
      'already_added': '1',
    });

    expect(r.comicvineId, 167340);
    expect(r.year, 2025);
    expect(r.issueCount, 3);
    expect(r.alreadyAdded, isTrue);
    expect(r.description, 'Collected & editions of the series.');
  });

  test('a missing already_added means not added', () {
    final r = KapowarrSearchResult.fromJson({
      'comicvine_id': 1,
      'title': 'T',
      'description': '',
    });
    expect(r.alreadyAdded, isFalse);
    expect(r.year, 0);
  });

  test('addVolume posts what Kapowarr requires, including special_version',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://kapowarr.test'));
    final adapter = DioAdapter(dio: dio);
    dio.httpClientAdapter = adapter;
    adapter.onGet('/api/rootfolder', (s) => s.reply(200, {
          'result': [
            {'id': 7, 'folder': '/comics/'}
          ]
        }));
    adapter.onPost(
      '/api/volumes',
      (s) => s.reply(201, {
        'result': {'id': 42}
      }),
      data: {
        'comicvine_id': 167340,
        'root_folder_id': 7,
        'monitor': true,
        'monitoring_scheme': 'all',
        'monitor_new_issues': true,
        'auto_search': true,
        // Omitting this makes Kapowarr reject the request.
        'special_version': 'auto',
      },
      queryParameters: {'api_key': 'k'},
    );
    final client = KapowarrClient(
      config: const KapowarrConfig(baseUrl: 'http://kapowarr.test', apiKey: 'k'),
      dio: dio,
    );

    expect(await client.addVolume(167340), 42);
  });
}
