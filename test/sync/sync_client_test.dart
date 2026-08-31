import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shaddai_reader/core/sync/sync_client.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late SyncClient client;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    adapter = DioAdapter(dio: dio);
    dio.httpClientAdapter = adapter;
    client = SyncClient(baseUrl: 'http://test.local', token: 'a-token', dio: dio);
  });

  test('login() returns the token and username', () async {
    adapter.onPost(
      '/auth/login',
      (server) => server.reply(200, {'token': 'new-token', 'username': 'paul'}),
      data: {'username': 'paul', 'password': 'hunter22'},
    );

    final result = await client.login(username: 'paul', password: 'hunter22');

    expect(result.token, 'new-token');
    expect(result.username, 'paul');
  });

  test('register() sends the invite code and returns a token', () async {
    adapter.onPost(
      '/auth/register',
      (server) => server.reply(200, {'token': 'fresh-token', 'username': 'friend'}),
      data: {
        'username': 'friend',
        'password': 'longenoughpw',
        'invite_code': 'let-me-in',
      },
    );

    final result = await client.register(
      username: 'friend',
      password: 'longenoughpw',
      inviteCode: 'let-me-in',
    );

    expect(result.token, 'fresh-token');
  });

  test('requests attach the bearer token from the current session', () async {
    adapter.onGet(
      '/auth/me',
      (server) => server.reply(200, {'username': 'paul'}),
      headers: {'Authorization': 'Bearer a-token'},
    );

    final username = await client.me();

    expect(username, 'paul');
  });

  test('updateToken() changes the token used on subsequent requests', () async {
    client.updateToken('swapped-token');
    adapter.onGet(
      '/auth/me',
      (server) => server.reply(200, {'username': 'paul'}),
      headers: {'Authorization': 'Bearer swapped-token'},
    );

    final username = await client.me();

    expect(username, 'paul');
  });

  test('pull() passes since as a query parameter and decodes records', () async {
    adapter.onGet(
      '/records/history',
      (server) => server.reply(200, {
        'records': [
          {
            'record_id': 'book-1',
            'data': {'bookTitle': 'Issue 1'},
            'updated_at': '2026-08-30T00:00:00.000Z',
            'deleted': false,
          },
        ],
      }),
      queryParameters: {'since': '2026-08-29T00:00:00.000Z'},
    );

    final records = await client.pull('history', since: '2026-08-29T00:00:00.000Z');

    expect(records, hasLength(1));
    expect(records.single.recordId, 'book-1');
    expect(records.single.data['bookTitle'], 'Issue 1');
  });

  test('pull() omits since when empty (full pull)', () async {
    adapter.onGet(
      '/records/history',
      (server) => server.reply(200, {'records': <Map<String, dynamic>>[]}),
    );

    final records = await client.pull('history');

    expect(records, isEmpty);
  });

  test('push() sends the record list and returns the merged server state',
      () async {
    adapter.onPut(
      '/records/history',
      (server) => server.reply(200, {
        'records': [
          {
            'record_id': 'book-1',
            'data': {'bookTitle': 'Issue 1'},
            'updated_at': '2026-08-30T00:00:00.000Z',
            'deleted': false,
          },
        ],
      }),
      data: [
        {
          'record_id': 'book-1',
          'data': {'bookTitle': 'Issue 1'},
          'updated_at': '2026-08-30T00:00:00.000Z',
          'deleted': false,
        },
      ],
    );

    final result = await client.push('history', [
      const SyncRecord(
        recordId: 'book-1',
        data: {'bookTitle': 'Issue 1'},
        updatedAt: '2026-08-30T00:00:00.000Z',
      ),
    ]);

    expect(result, hasLength(1));
    expect(result.single.recordId, 'book-1');
  });
}
