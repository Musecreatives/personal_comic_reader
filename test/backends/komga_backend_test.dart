import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shaddai_reader/backends/komga/komga_backend.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late KomgaBackend backend;

  const config = ServerConfig(
    id: 's1',
    name: 'Test Komga',
    type: ServerType.komga,
    baseUrl: 'http://test.local',
    username: 'user@example.org',
  );

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: config.baseUrl));
    adapter = DioAdapter(dio: dio);
    dio.httpClientAdapter = adapter;
    backend = KomgaBackend(config: config, password: 'pw', dio: dio);
  });

  test('authenticate() calls /api/v2/users/me and succeeds on 200', () async {
    adapter.onGet(
      '/api/v2/users/me',
      (server) => server.reply(200, {'id': 'u1', 'email': 'user@example.org'}),
    );

    await backend.authenticate();
    // No exception thrown = success.
  });

  test('authenticate() throws on 401', () async {
    adapter.onGet(
      '/api/v2/users/me',
      (server) => server.reply(401, {'message': 'unauthorized'}),
    );

    expect(() => backend.authenticate(), throwsA(isA<DioException>()));
  });

  test('listLibraries() maps id/name from the response', () async {
    adapter.onGet(
      '/api/v1/libraries',
      (server) => server.reply(200, [
        {'id': 'lib1', 'name': 'Comics'},
        {'id': 'lib2', 'name': 'Manga'},
      ]),
    );

    final libraries = await backend.listLibraries();

    expect(libraries, hasLength(2));
    expect(libraries[0].id, 'lib1');
    expect(libraries[0].name, 'Comics');
    expect(libraries[1].name, 'Manga');
  });

  test('listSeries() parses the Spring Pageable envelope', () async {
    adapter.onPost(
      '/api/v1/series/list',
      (server) => server.reply(200, {
        'content': [
          {
            'id': 'series1',
            'libraryId': 'lib1',
            'name': 'Fallback Name',
            'booksCount': 10,
            'booksReadCount': 3,
            'booksUnreadCount': 7,
            'metadata': {'title': 'Absolute Batman'},
            'booksMetadata': {'summary': 'A dark knight story.'},
          },
        ],
        'number': 0,
        'size': 20,
        'totalPages': 1,
        'totalElements': 1,
      }),
      data: Matchers.any,
      queryParameters: {'page': 0, 'size': 20, 'sort': 'metadata.titleSort,asc'},
    );

    final result = await backend.listSeries(libraryId: 'lib1');

    expect(result.totalElements, 1);
    expect(result.items.single.title, 'Absolute Batman');
    expect(result.items.single.summary, 'A dark knight story.');
    expect(result.items.single.booksUnreadCount, 7);
  });

  test('listSeries() falls back to name when metadata.title is absent',
      () async {
    adapter.onPost(
      '/api/v1/series/list',
      (server) => server.reply(200, {
        'content': [
          {
            'id': 'series2',
            'libraryId': 'lib1',
            'name': 'Raw Folder Name',
            'booksCount': 1,
            'booksReadCount': 0,
            'booksUnreadCount': 1,
            'metadata': <String, dynamic>{},
          },
        ],
        'number': 0,
        'size': 20,
        'totalPages': 1,
        'totalElements': 1,
      }),
      data: Matchers.any,
      queryParameters: {'page': 0, 'size': 20, 'sort': 'metadata.titleSort,asc'},
    );

    final result = await backend.listSeries();

    expect(result.items.single.title, 'Raw Folder Name');
  });

  test('updateProgress() converts to 1-based page and PATCHes', () async {
    adapter.onPatch(
      '/api/v1/books/book1/read-progress',
      (server) => server.reply(204, null),
      data: {'page': 6, 'completed': false},
    );

    await backend.updateProgress('book1', page: 5);
    // No exception = the mock matched the expected body/path.
  });

  test('thumbnailUrlForSeries() builds a full URL under the base', () {
    expect(
      backend.thumbnailUrlForSeries('series1'),
      'http://test.local/api/v1/series/series1/thumbnail',
    );
  });
}
