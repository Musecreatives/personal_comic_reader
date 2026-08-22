import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shaddai_reader/core/kapowarr/kapowarr_client.dart';
import 'package:shaddai_reader/core/kapowarr/kapowarr_config.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late KapowarrClient client;

  const config =
      KapowarrConfig(baseUrl: 'http://test.local', apiKey: 'secret-key');

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: config.baseUrl));
    adapter = DioAdapter(dio: dio);
    dio.httpClientAdapter = adapter;
    client = KapowarrClient(config: config, dio: dio);
  });

  test('getStats() attaches api_key and parses the result envelope',
      () async {
    adapter.onGet(
      '/api/volumes/stats',
      (server) => server.reply(200, {
        'error': null,
        'result': {
          'volumes': 4,
          'monitored': 4,
          'unmonitored': 0,
          'issues': 34,
          'downloaded_issues': 3,
          'files': 3,
          'total_file_size': 172871566,
        },
      }),
      queryParameters: {'api_key': 'secret-key'},
    );

    final stats = await client.getStats();

    expect(stats.volumes, 4);
    expect(stats.downloadedIssues, 3);
    expect(stats.totalFileSize, 172871566);
  });

  test('getQueue() maps queue items, falling back to file_title', () async {
    adapter.onGet(
      '/api/activity/queue',
      (server) => server.reply(200, {
        'error': null,
        'result': [
          {'file_title': 'Some Comic Issue 001', 'source': 'GetComics'},
        ],
      }),
      queryParameters: {'api_key': 'secret-key'},
    );

    final queue = await client.getQueue();

    expect(queue.single.title, 'Some Comic Issue 001');
    expect(queue.single.source, 'GetComics');
  });

  test('getHistory() parses downloaded_at as a DateTime and respects limit',
      () async {
    adapter.onGet(
      '/api/activity/history',
      (server) => server.reply(200, {
        'error': null,
        'result': [
          {
            'web_title': 'One World Under Doom #6 (2025)',
            'source': 'GetComics',
            'downloaded_at': 1787419822,
            'success': true,
          },
          {
            'web_title': 'One World Under Doom #4 (2025)',
            'source': 'GetComics',
            'downloaded_at': 1787419802,
            'success': true,
          },
        ],
      }),
      queryParameters: {'api_key': 'secret-key'},
    );

    final history = await client.getHistory(limit: 1);

    expect(history, hasLength(1));
    expect(history.single.title, 'One World Under Doom #6 (2025)');
    expect(history.single.success, true);
  });
}
