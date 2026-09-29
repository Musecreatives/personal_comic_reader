import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';
import 'package:shaddai_reader/core/comicvine/comicvine_key_store.dart';
import 'package:shaddai_reader/core/kapowarr/kapowarr_config_store.dart';
import 'package:shaddai_reader/core/media_pool/media_pool_config_store.dart';
import 'package:shaddai_reader/core/storage/server_store.dart';
import 'package:shaddai_reader/core/sync/connections_sync.dart';
import 'package:shaddai_reader/core/sync/sync_client.dart';
import 'package:shaddai_reader/core/sync/sync_queue.dart';

void main() {
  late DioAdapter adapter;
  late ServerStore servers;
  late KapowarrConfigStore kapowarr;
  late ComicVineKeyStore comicVine;
  late ConnectionsSync connections;
  final pushed = <Map<String, dynamic>>[];

  setUp(() async {
    await setUpTestHive();
    FlutterSecureStorage.setMockInitialValues({});
    pushed.clear();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    adapter = DioAdapter(dio: dio);
    dio.httpClientAdapter = adapter;
    adapter.onPut('/records/connections', (s) => s.reply(200, {'records': []}),
        data: Matchers.any);
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (o.method == 'PUT') {
        pushed.addAll((o.data as List).cast<Map<String, dynamic>>());
      }
      h.next(o);
    }));

    servers = ServerStore();
    await servers.init();
    kapowarr = KapowarrConfigStore();
    await kapowarr.init();
    comicVine = ComicVineKeyStore();
    final mediaPool = MediaPoolConfigStore();
    await mediaPool.init();
    connections = ConnectionsSync(
      servers: servers,
      kapowarr: kapowarr,
      comicVine: comicVine,
      mediaPool: mediaPool,
    );
    await connections.init();
    final queue = SyncQueue();
    await queue.init();
    connections.sync.attach(
        SyncClient(baseUrl: 'http://test.local', token: 't', dio: dio), queue);
  });
  tearDown(() async => await tearDownTestHive());

  Map<String, dynamic> rec(String id, Map<String, dynamic> data,
          {bool deleted = false, String at = '2026-09-02T00:00:00.000Z'}) =>
      {
        'record_id': id,
        'data': {...data, '_at': at},
        'updated_at': at,
        'deleted': deleted,
      };

  void pulls(List<Map<String, dynamic>> records) => adapter.onGet(
      '/records/connections', (s) => s.reply(200, {'records': records}));

  const komgaKey = 'server|komga|https://reader.example/komga';
  final komga = {
    'name': 'Komga',
    'type': 'komga',
    'baseUrl': 'https://reader.example/komga',
    'username': 'me@example.com',
    'password': 'hunter2',
  };

  test('a fresh install gets every connection from the account', () async {
    pulls([
      rec(komgaKey, komga),
      rec('kapowarr', {'baseUrl': 'http://k.example', 'apiKey': 'abc'}),
      rec('comicvine', {'apiKey': 'cv-key'}),
    ]);

    expect(await connections.reconcile(), isTrue);

    final s = servers.listServers().single;
    expect(s.type, ServerType.komga);
    expect(s.username, 'me@example.com');
    expect(await servers.getPassword(s.id), 'hunter2');
    expect(servers.getActiveServerId(), s.id);
    expect((await kapowarr.getWithApiKey())!.apiKey, 'abc');
    expect(await comicVine.get(), 'cv-key');
    expect(pushed, isEmpty); // nothing new to send back
  });

  test('a server deleted on another device is removed here', () async {
    pulls([rec(komgaKey, komga)]);
    await connections.reconcile();
    expect(servers.listServers(), hasLength(1));

    // Next pull (since the last one) carries the tombstone.
    adapter.onGet('/records/connections',
        (s) => s.reply(200, {
              'records': [
                rec(komgaKey, {},
                    deleted: true, at: '2026-09-03T00:00:00.000Z')
              ]
            }),
        queryParameters: {'since': '2026-09-02T00:00:00.000Z'});
    expect(await connections.reconcile(), isTrue);
    expect(servers.listServers(), isEmpty);
  });

  test('a server only this device has is uploaded, password included',
      () async {
    await servers.saveServer(
      const ServerConfig(
        id: 'local-id',
        name: 'Suwayomi',
        type: ServerType.suwayomi,
        baseUrl: 'https://reader.example/suwayomi',
        username: '',
      ),
      password: 'pw',
    );
    pulls([]);
    await connections.reconcile();

    // Pushed on save, and again by the first sync's upload of records the
    // server hasn't confirmed yet - both must carry the password.
    final ups = pushed.where((r) =>
        r['record_id'] == 'server|suwayomi|https://reader.example/suwayomi');
    expect(ups, isNotEmpty);
    for (final up in ups) {
      expect(up['data']['password'], 'pw');
      expect(up['deleted'], isFalse);
    }
  });
}
