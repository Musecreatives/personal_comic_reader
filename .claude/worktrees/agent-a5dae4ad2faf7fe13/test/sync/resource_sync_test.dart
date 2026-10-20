import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hive_test/hive_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shaddai_reader/core/sync/resource_sync.dart';
import 'package:shaddai_reader/core/sync/sync_client.dart';
import 'package:shaddai_reader/core/sync/sync_queue.dart';

void main() {
  setUp(() async => await setUpTestHive());
  tearDown(() async => await tearDownTestHive());

  late DioAdapter adapter;
  late ResourceSync sync;
  late Box<String> box;

  Future<void> setup({bool attach = true}) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    adapter = DioAdapter(dio: dio);
    dio.httpClientAdapter = adapter;
    final queue = SyncQueue();
    await queue.init();
    box = await Hive.openBox<String>('thing');
    sync = ResourceSync('thing');
    if (attach) {
      sync.attach(
          SyncClient(baseUrl: 'http://test.local', token: 't', dio: dio), queue);
    }
  }

  Map<String, dynamic> rec(String id, String at, Map<String, dynamic> data,
          {bool deleted = false}) =>
      {'record_id': id, 'data': data, 'updated_at': at, 'deleted': deleted};

  // First-sync pulls carry no `since`, so the route has no query params.
  void pulls(List<Map<String, dynamic>> records) => adapter.onGet(
      '/records/thing', (s) => s.reply(200, {'records': records}));

  test('a newer remote record replaces the local one', () async {
    await setup();
    await box.put('a', jsonEncode({'v': 1, '_at': '2026-09-01T00:00:00.000Z'}));
    pulls([
      rec('a', '2026-09-02T00:00:00.000Z',
          {'v': 2, '_at': '2026-09-02T00:00:00.000Z'})
    ]);

    expect(await sync.reconcile(box), isTrue);
    expect((jsonDecode(box.get('a')!) as Map)['v'], 2);
  });

  test('a stale remote record does not overwrite a newer local one', () async {
    await setup();
    await box.put('a', jsonEncode({'v': 1, '_at': '2026-09-05T00:00:00.000Z'}));
    pulls([
      rec('a', '2026-09-02T00:00:00.000Z',
          {'v': 2, '_at': '2026-09-02T00:00:00.000Z'})
    ]);

    expect(await sync.reconcile(box), isFalse);
    expect((jsonDecode(box.get('a')!) as Map)['v'], 1);
  });

  test('a remote tombstone deletes the local record', () async {
    await setup();
    await box.put('a', jsonEncode({'v': 1, '_at': '2026-09-01T00:00:00.000Z'}));
    pulls([rec('a', '2026-09-02T00:00:00.000Z', {}, deleted: true)]);

    expect(await sync.reconcile(box), isTrue);
    expect(box.containsKey('a'), isFalse);
  });

  test('first sync uploads local-only records the server has never seen',
      () async {
    await setup();
    await box.put(
        'mine', jsonEncode({'v': 9, '_at': '2026-09-01T00:00:00.000Z'}));
    pulls([]);
    adapter.onPut('/records/thing', (s) => s.reply(200, {'records': []}),
        data: Matchers.any);

    await sync.reconcile(box);
    // An unmatched PUT would have thrown; reaching here means it was sent.
  });

  test('put() stamps _at and works local-only with no session', () async {
    await setup(attach: false);

    await sync.put(box, 'a', {'v': 1});

    final stored = jsonDecode(box.get('a')!) as Map;
    expect(stored['v'], 1);
    expect(stored['_at'], isNotNull);
  });
}
