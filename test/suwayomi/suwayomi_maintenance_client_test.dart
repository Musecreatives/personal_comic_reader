import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shaddai_reader/backends/suwayomi/suwayomi_maintenance_client.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late SuwayomiMaintenanceClient client;

  const config = ServerConfig(
    id: 's1',
    name: 'Suwayomi',
    type: ServerType.suwayomi,
    baseUrl: 'http://test.local',
    username: '',
  );

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: config.baseUrl));
    adapter = DioAdapter(dio: dio);
    dio.httpClientAdapter = adapter;
    client = SuwayomiMaintenanceClient(config: config, dio: dio);
  });

  test('libraryHealth() sums manga counts across every category', () async {
    adapter.onPost(
      '/api/graphql',
      (server) => server.reply(200, {
        'data': {
          'categories': {
            'nodes': [
              {'mangas': {'totalCount': 1}},
              {'mangas': {'totalCount': 58}},
              {'mangas': {'totalCount': 40}},
            ],
          },
        },
      }),
      data: Matchers.any,
    );

    final health = await client.libraryHealth();

    expect(health.categoryCount, 3);
    expect(health.totalManga, 99);
  });

  test('extensionStatus() reports install state only for known packages',
      () async {
    adapter.onPost(
      '/api/graphql',
      (server) => server.reply(200, {
        'data': {
          'fetchExtensions': {
            'extensions': [
              {
                'pkgName': 'eu.kanade.tachiyomi.extension.en.mangabat',
                'isInstalled': true,
              },
              {
                'pkgName': 'eu.kanade.tachiyomi.extension.en.flamecomics',
                'isInstalled': false,
              },
              {
                'pkgName': 'eu.kanade.tachiyomi.extension.all.somethingelse',
                'isInstalled': true,
              },
            ],
          },
        },
      }),
      data: Matchers.any,
    );

    final statuses = await client.extensionStatus();

    expect(statuses.length, knownExtensionPackages.length);
    final mangabat = statuses.firstWhere((e) => e.name == 'Mangabat');
    expect(mangabat.isInstalled, true);
    final flame = statuses.firstWhere((e) => e.name == 'Flame Comics');
    expect(flame.isInstalled, false);
  });

  test('reinstallExtension() succeeds when the server accepts it', () async {
    adapter.onPost(
      '/api/graphql',
      (server) => server.reply(200, {
        'data': {
          'updateExtension': {
            'extension': {'pkgName': 'eu.kanade.tachiyomi.extension.en.mangabat'},
          },
        },
      }),
      data: Matchers.any,
    );

    await client.reinstallExtension('eu.kanade.tachiyomi.extension.en.mangabat');
  });

  test('reinstallExtension() throws StaleExtensionFileException on a stale jar',
      () async {
    adapter.onPost(
      '/api/graphql',
      (server) => server.reply(200, {
        'data': null,
        'errors': [
          {'message': 'java.nio.file.FileAlreadyExistsException: ...'}
        ],
      }),
      data: Matchers.any,
    );

    expect(
      () => client.reinstallExtension('eu.kanade.tachiyomi.extension.en.mangabat'),
      throwsA(isA<StaleExtensionFileException>()),
    );
  });

  test('createBackup() returns the download url', () async {
    adapter.onPost(
      '/api/graphql',
      (server) => server.reply(200, {
        'data': {
          'createBackup': {'url': '/api/v1/backup/file.tachibk'},
        },
      }),
      data: Matchers.any,
    );

    final url = await client.createBackup();

    expect(url, '/api/v1/backup/file.tachibk');
  });
}
