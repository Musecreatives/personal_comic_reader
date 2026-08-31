import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shaddai_reader/core/history/history_entry.dart';
import 'package:shaddai_reader/core/history/history_store.dart';
import 'package:shaddai_reader/core/sync/sync_client.dart';
import 'package:shaddai_reader/core/sync/sync_queue.dart';

void main() {
  setUp(() async => await setUpTestHive());
  tearDown(() async => await tearDownTestHive());

  HistoryEntry entry({
    String bookId = 'book-1',
    DateTime? timestamp,
    String bookTitle = 'Issue 1',
  }) =>
      HistoryEntry(
        bookId: bookId,
        seriesId: 'series-1',
        bookTitle: bookTitle,
        bookNumber: '1',
        pageCount: 20,
        lastPage: 19,
        completed: true,
        timestamp: timestamp ?? DateTime.utc(2026, 8, 30),
      );

  test('record() works locally with no sync attached (backward compatible)',
      () async {
    final store = HistoryStore();
    await store.init();

    await store.record(entry());

    expect(store.list(), hasLength(1));
    expect(store.list().single.bookId, 'book-1');
  });

  test('record() enqueues a push once sync is attached', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    final adapter = DioAdapter(dio: dio);
    dio.httpClientAdapter = adapter;
    final client =
        SyncClient(baseUrl: 'http://test.local', token: 'a-token', dio: dio);
    final queue = SyncQueue();
    await queue.init();

    final store = HistoryStore();
    await store.init();
    store.attachSync(client, queue);

    final e = entry();
    adapter.onPut(
      '/records/history',
      (server) => server.reply(200, {
        'records': [
          {
            'record_id': e.bookId,
            'data': e.toJson(),
            'updated_at': e.timestamp.toIso8601String(),
            'deleted': false,
          },
        ],
      }),
      data: [
        {
          'record_id': e.bookId,
          'data': e.toJson(),
          'updated_at': e.timestamp.toIso8601String(),
          'deleted': false,
        },
      ],
    );

    await store.record(e);

    // If the push hadn't actually gone out with this exact body, the
    // adapter route above wouldn't have matched and record() would have
    // thrown - reaching here proves the queue pushed it.
    expect(store.list(), hasLength(1));
  });

  test('reconcile() pulls remote entries the local box has never seen',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    final adapter = DioAdapter(dio: dio);
    dio.httpClientAdapter = adapter;
    final client =
        SyncClient(baseUrl: 'http://test.local', token: 'a-token', dio: dio);
    final queue = SyncQueue();
    await queue.init();

    final store = HistoryStore();
    await store.init();
    store.attachSync(client, queue);

    final remoteEntry = entry(bookId: 'book-2', bookTitle: 'From another device');
    adapter.onGet(
      '/records/history',
      (server) => server.reply(200, {
        'records': [
          {
            'record_id': remoteEntry.bookId,
            'data': remoteEntry.toJson(),
            'updated_at': remoteEntry.timestamp.toIso8601String(),
            'deleted': false,
          },
        ],
      }),
    );

    await store.reconcile();

    expect(store.list(), hasLength(1));
    expect(store.list().single.bookTitle, 'From another device');
  });

  test('reconcile() does not overwrite a newer local entry with a stale remote one',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    final adapter = DioAdapter(dio: dio);
    dio.httpClientAdapter = adapter;
    final client =
        SyncClient(baseUrl: 'http://test.local', token: 'a-token', dio: dio);
    final queue = SyncQueue();
    await queue.init();

    final store = HistoryStore();
    await store.init();

    final newerLocal = entry(
      timestamp: DateTime.utc(2026, 8, 30, 12),
      bookTitle: 'Newer local read',
    );
    await store.record(newerLocal); // no sync attached yet - stays local

    store.attachSync(client, queue);

    final staleRemote = entry(
      timestamp: DateTime.utc(2026, 8, 30, 6),
      bookTitle: 'Stale remote read',
    );
    adapter.onGet(
      '/records/history',
      (server) => server.reply(200, {
        'records': [
          {
            'record_id': staleRemote.bookId,
            'data': staleRemote.toJson(),
            'updated_at': staleRemote.timestamp.toIso8601String(),
            'deleted': false,
          },
        ],
      }),
    );

    await store.reconcile();

    expect(store.list().single.bookTitle, 'Newer local read');
  });
}
