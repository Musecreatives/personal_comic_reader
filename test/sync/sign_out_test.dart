import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hive_test/hive_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shaddai_reader/app/providers.dart';
import 'package:shaddai_reader/core/appearance/appearance_store.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';
import 'package:shaddai_reader/core/collections/collections_store.dart';
import 'package:shaddai_reader/core/comicvine/comicvine_key_store.dart';
import 'package:shaddai_reader/core/history/history_entry.dart';
import 'package:shaddai_reader/core/history/history_store.dart';
import 'package:shaddai_reader/core/kapowarr/kapowarr_config_store.dart';
import 'package:shaddai_reader/core/media_pool/media_pool_config_store.dart';
import 'package:shaddai_reader/core/reader/reader_settings_store.dart';
import 'package:shaddai_reader/core/sources/hidden_sources_store.dart';
import 'package:shaddai_reader/core/stats/reading_stats_store.dart';
import 'package:shaddai_reader/core/storage/server_store.dart';
import 'package:shaddai_reader/core/sync/auth_store.dart';
import 'package:shaddai_reader/core/sync/connections_sync.dart';
import 'package:shaddai_reader/core/sync/sync_client.dart';
import 'package:shaddai_reader/core/sync/sync_queue.dart';

void main() {
  setUp(() async {
    await setUpTestHive();
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() async => await tearDownTestHive());

  test('sign out leaves nothing of the account for the next one', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    final adapter = DioAdapter(dio: dio);
    dio.httpClientAdapter = adapter;
    adapter.onPost('/auth/logout', (s) => s.reply(200, {}));
    for (final r in ['connections', 'history', 'collections']) {
      adapter.onPut('/records/$r', (s) => s.reply(200, {'records': []}),
          data: Matchers.any);
    }
    final client =
        SyncClient(baseUrl: 'http://test.local', token: 't', dio: dio);

    final servers = ServerStore();
    await servers.init();
    final kapowarr = KapowarrConfigStore();
    await kapowarr.init();
    final mediaPool = MediaPoolConfigStore();
    await mediaPool.init();
    final comicVine = ComicVineKeyStore();
    final connections = ConnectionsSync(
        servers: servers,
        kapowarr: kapowarr,
        comicVine: comicVine,
        mediaPool: mediaPool);
    await connections.init();
    final queue = SyncQueue();
    await queue.init();
    connections.sync.attach(client, queue);
    final history = HistoryStore();
    await history.init();
    final collections = CollectionsStore();
    await collections.init();
    collections.sync.attach(client, queue);
    final appearance = AppearanceStore();
    await appearance.init();
    final reader = ReaderSettingsStore();
    await reader.init();
    final stats = ReadingStatsStore();
    await stats.init();
    final hidden = HiddenSourcesStore();
    await hidden.init();
    final auth = AuthStore();
    await auth.saveSession(token: 't', username: 'owner');

    await servers.saveServer(
        const ServerConfig(
            id: 's1',
            name: 'Komga',
            type: ServerType.komga,
            baseUrl: 'https://reader.example/komga',
            username: 'me@example.com'),
        password: 'hunter2');
    await servers.setActiveServerId('s1');
    await connections.pushLocal();
    await history.record(HistoryEntry(
      serverId: 's1',
      bookId: 'b1',
      seriesId: 'series-1',
      bookTitle: 'Chapter 1',
      bookNumber: '1',
      pageCount: 20,
      lastPage: 3,
      completed: false,
      timestamp: DateTime.utc(2026, 11, 15),
    ));
    await collections.create('Favourites');

    final c = ProviderContainer(overrides: [
      syncClientProvider.overrideWithValue(client),
      syncQueueProvider.overrideWithValue(queue),
      serverStoreProvider.overrideWithValue(servers),
      kapowarrConfigStoreProvider.overrideWithValue(kapowarr),
      mediaPoolConfigStoreProvider.overrideWithValue(mediaPool),
      comicVineKeyStoreProvider.overrideWithValue(comicVine),
      connectionsSyncProvider.overrideWithValue(connections),
      historyStoreProvider.overrideWithValue(history),
      collectionsStoreProvider.overrideWithValue(collections),
      appearanceStoreProvider.overrideWithValue(appearance),
      appearanceProvider.overrideWith((ref) => appearance.get()),
      readerSettingsStoreProvider.overrideWithValue(reader),
      readingStatsStoreProvider.overrideWithValue(stats),
      hiddenSourcesStoreProvider.overrideWithValue(hidden),
      authStoreProvider.overrideWithValue(auth),
      currentUsernameProvider.overrideWith((ref) => 'owner'),
    ]);

    await signOut(c);

    expect(servers.listServers(), isEmpty);
    expect(await servers.getPassword('s1'), isNull);
    expect(history.list(), isEmpty);
    expect(collections.list(), isEmpty);
    expect(Hive.box<String>('connections').isEmpty, isTrue);
    expect(await auth.getToken(), isNull);
    expect(c.read(currentUsernameProvider), isNull);
    expect(c.read(activeServerIdProvider), isNull);

    // Edits after sign-out stay local: nothing is queued for any account.
    await collections.create('Next account');
    expect(Hive.box<String>('sync_queue').isEmpty, isTrue);
  });
}
