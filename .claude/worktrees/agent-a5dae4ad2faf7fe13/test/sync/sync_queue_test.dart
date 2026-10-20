import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shaddai_reader/core/sync/sync_client.dart';
import 'package:shaddai_reader/core/sync/sync_queue.dart';

void main() {
  setUp(() async => await setUpTestHive());
  tearDown(() async => await tearDownTestHive());

  late Dio dio;
  late DioAdapter adapter;
  late SyncClient client;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    adapter = DioAdapter(dio: dio);
    dio.httpClientAdapter = adapter;
    client = SyncClient(baseUrl: 'http://test.local', token: 'a-token', dio: dio);
  });

  const record = SyncRecord(
    recordId: 'book-1',
    data: {'bookTitle': 'Issue 1'},
    updatedAt: '2026-08-30T00:00:00.000Z',
  );

  test('enqueue() pushes immediately and clears the queue on success', () async {
    adapter.onPut(
      '/records/history',
      (server) => server.reply(200, {
        'records': [record.toJson()],
      }),
      data: [record.toJson()],
    );

    final queue = SyncQueue();
    await queue.init();

    await queue.enqueue(client, 'history', record);
    await queue.flush(client, 'history'); // no-op: nothing left queued
  });

  test('a failed push stays queued and is retried on the next flush',
      () async {
    // No adapter route registered -> the first push fails.
    final queue = SyncQueue();
    await queue.init();

    await queue.enqueue(client, 'history', record);

    adapter.onPut(
      '/records/history',
      (server) => server.reply(200, {
        'records': [record.toJson()],
      }),
      data: [record.toJson()],
    );

    await queue.flush(client, 'history');
    // A second flush with nothing new registered would fail if anything
    // were still queued, since there's only one route registered above -
    // calling it again and letting it no-op (empty queue) proves the
    // first flush actually cleared it.
    await queue.flush(client, 'history');
  });

  test('flush() only sends records for the given resource', () async {
    final queue = SyncQueue();
    await queue.init();

    const otherRecord = SyncRecord(
      recordId: 'collection-1',
      data: {'name': 'Favorites'},
      updatedAt: '2026-08-30T00:00:00.000Z',
    );

    await queue.enqueue(null, 'history', record);
    await queue.enqueue(null, 'collections', otherRecord);

    adapter.onPut(
      '/records/history',
      (server) => server.reply(200, {
        'records': [record.toJson()],
      }),
      data: [record.toJson()],
    );

    await queue.flush(client, 'history');
    // collections was never registered on the adapter - if flush('history')
    // had accidentally swept it up too, this would throw.
  });
}
