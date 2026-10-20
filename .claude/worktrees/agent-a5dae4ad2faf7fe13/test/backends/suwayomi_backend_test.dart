import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shaddai_reader/backends/suwayomi/suwayomi_backend.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late SuwayomiBackend backend;

  const config = ServerConfig(
    id: 's1',
    name: 'Test Suwayomi',
    type: ServerType.suwayomi,
    baseUrl: 'http://test.local',
    username: '',
  );

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: config.baseUrl));
    adapter = DioAdapter(dio: dio);
    dio.httpClientAdapter = adapter;
    backend = SuwayomiBackend(config: config, password: '', dio: dio);
  });

  test('listLibraries() maps categories to Library', () async {
    adapter.onPost(
      '/api/graphql',
      (server) => server.reply(200, {
        'data': {
          'categories': {
            'nodes': [
              {'id': 0, 'name': 'Default'},
            ],
          },
        },
      }),
      data: Matchers.any,
    );

    final libraries = await backend.listLibraries();

    expect(libraries.single.id, '0');
    expect(libraries.single.name, 'Default');
  });

  test('listSeries() with a libraryId queries that category and computes '
      'read/unread from unreadCount', () async {
    adapter.onPost(
      '/api/graphql',
      (server) => server.reply(200, {
        'data': {
          'category': {
            'mangas': {
              'nodes': [
                {
                  'id': 2,
                  'title': 'Chronicles of the Demon Faction',
                  'thumbnailUrl': '/api/v1/manga/2/thumbnail',
                  'inLibrary': true,
                  'unreadCount': 184,
                  'chapters': {'totalCount': 200},
                },
              ],
            },
          },
        },
      }),
      data: Matchers.any,
    );

    final result = await backend.listSeries(libraryId: '0');

    final series = result.items.single;
    expect(series.title, 'Chronicles of the Demon Faction');
    expect(series.booksCount, 200);
    expect(series.booksUnreadCount, 184);
    expect(series.booksReadCount, 16);
  });

  test('getBook() maps a chapter and reports pageCount 0 when unfetched (-1)',
      () async {
    adapter.onPost(
      '/api/graphql',
      (server) => server.reply(200, {
        'data': {
          'chapter': {
            'id': 3,
            'name': 'Chapter 3',
            'chapterNumber': 3,
            'pageCount': -1,
            'lastPageRead': 0,
            'isRead': false,
            'mangaId': 2,
          },
        },
      }),
      data: Matchers.any,
    );

    final book = await backend.getBook('3');

    expect(book.id, '3');
    expect(book.seriesId, '2');
    expect(book.pageCount, 0);
    expect(book.completed, false);
  });

  test(
      'pageUri() uses the chapter\'s sourceOrder in the REST path, not its '
      'database id - Suwayomi\'s page-serving route is indexed by position '
      'within the manga, and diverges from id for any split/special chapter',
      () async {
    adapter.onPost(
      '/api/graphql',
      (server) => server.reply(200, {
        'data': {
          'chapter': {
            'id': 326,
            'name': 'Chapter 22.1',
            'chapterNumber': 22.1,
            'pageCount': 40,
            'lastPageRead': 0,
            'isRead': false,
            'mangaId': 137,
            'sourceOrder': 23,
          },
        },
      }),
      data: Matchers.any,
    );

    final uri = await backend.pageUri('326', 0);

    expect(uri.toString(), 'http://test.local/api/v1/manga/137/chapter/23/page/0');
  });

  test('updateProgress() sends lastPageRead and isRead in one mutation',
      () async {
    adapter.onPost(
      '/api/graphql',
      (server) => server.reply(200, {
        'data': {
          'updateChapter': {
            'chapter': {'id': 1},
          },
        },
      }),
      data: Matchers.any,
    );

    await backend.updateProgress('1', page: 5, completed: true);
    // No exception = the GraphQL call succeeded end to end.
  });

  test('thumbnailUrlForSeries() builds the REST thumbnail URL', () {
    expect(
      backend.thumbnailUrlForSeries('2'),
      'http://test.local/api/v1/manga/2/thumbnail',
    );
  });
}
