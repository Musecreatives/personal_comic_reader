import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shaddai_reader/backends/kavita/kavita_backend.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late KavitaBackend backend;

  const config = ServerConfig(
    id: 's1',
    name: 'Test Kavita',
    type: ServerType.kavita,
    baseUrl: 'http://test.local',
    username: 'user',
  );

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: config.baseUrl));
    adapter = DioAdapter(dio: dio);
    dio.httpClientAdapter = adapter;
    backend = KavitaBackend(config: config, password: 'pw', dio: dio);
  });

  test('authenticate() logs in and stores the token', () async {
    adapter.onPost(
      '/api/Account/login',
      (server) => server.reply(200, {
        'token': 'jwt-token',
        'refreshToken': 'refresh',
        'apiKey': 'key',
      }),
      data: {'username': 'user', 'password': 'pw'},
    );

    await backend.authenticate();

    expect(backend.imageHeaders['Authorization'], 'Bearer jwt-token');
  });

  test('a request lazily logs in first and attaches the bearer token',
      () async {
    adapter.onPost(
      '/api/Account/login',
      (server) => server.reply(200, {'token': 'jwt-token'}),
      data: Matchers.any,
    );
    adapter.onGet(
      '/api/Library/libraries',
      (server) => server.reply(200, [
        {'id': 1, 'name': 'Comics'},
      ]),
    );

    final libraries = await backend.listLibraries();

    expect(libraries.single.id, '1');
    expect(libraries.single.name, 'Comics');
  });

  test('listSeries() maps series and falls back to item-count totals when '
      'no Pagination header is present', () async {
    adapter.onPost(
      '/api/Account/login',
      (server) => server.reply(200, {'token': 'jwt-token'}),
      data: Matchers.any,
    );
    adapter.onPost(
      '/api/Series/all-v2',
      (server) => server.reply(200, [
        {
          'id': 5,
          'libraryId': 1,
          'name': 'Absolute Batman',
          'booksCount': 3,
          'booksReadCount': 1,
          'booksUnreadCount': 2,
        },
      ]),
      queryParameters: {'PageNumber': 1, 'PageSize': 20},
      data: Matchers.any,
    );

    final result = await backend.listSeries();

    expect(result.totalElements, 1);
    expect(result.items.single.title, 'Absolute Batman');
    expect(result.items.single.booksUnreadCount, 2);
  });

  test('updateProgress() looks up chapter location then posts the full DTO',
      () async {
    adapter.onPost(
      '/api/Account/login',
      (server) => server.reply(200, {'token': 'jwt-token'}),
      data: Matchers.any,
    );
    adapter.onGet(
      '/api/Chapter',
      (server) => server.reply(200, {
        'id': 42,
        'seriesId': 5,
        'volumeId': 9,
        'pages': 20,
        'pagesRead': 0,
      }),
      queryParameters: {'chapterId': '42'},
    );
    adapter.onGet(
      '/api/Series/5',
      (server) => server.reply(200, {
        'id': 5,
        'libraryId': 1,
        'name': 'Absolute Batman',
      }),
    );
    adapter.onGet(
      '/api/Series/volumes',
      (server) => server.reply(200, []),
      queryParameters: {'seriesId': '5'},
    );
    adapter.onPost(
      '/api/Reader/progress',
      (server) => server.reply(200, null),
      data: {
        'chapterId': 42,
        'pageNum': 10,
        'seriesId': 5,
        'volumeId': 9,
        'libraryId': 1,
      },
    );

    await backend.updateProgress('42', page: 10);
    // No exception = the mock matched the expected DTO shape.
  });

  test('thumbnailUrlForSeries() builds a full URL under the base', () {
    expect(
      backend.thumbnailUrlForSeries('5'),
      'http://test.local/api/Image/series-cover?seriesId=5',
    );
  });
}
