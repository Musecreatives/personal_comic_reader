import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shaddai_reader/backends/suwayomi/member_library.dart';
import 'package:shaddai_reader/backends/suwayomi/suwayomi_backend.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';

/// A friend's connection through the gateway: their library and progress
/// come from /shaddai/*, not Suwayomi's own library flags.
void main() {
  group('memberChapterState', () {
    test('an imported read-through marks earlier chapters read', () {
      expect(memberChapterState(number: 10, readThrough: 186).read, isTrue);
      expect(memberChapterState(number: 186, readThrough: 186).read, isTrue);
      expect(memberChapterState(number: 187, readThrough: 186).read, isFalse);
    });

    test('unnumbered chapters and titles with nothing read stay unread', () {
      expect(memberChapterState(number: -1, readThrough: 186).read, isFalse);
      expect(memberChapterState(number: 3, readThrough: null).read, isFalse);
    });

    test('their own record wins over the read-through', () {
      final s = memberChapterState(number: 10, readThrough: 186, record: {'read': false, 'page': 4});
      expect(s.read, isFalse);
      expect(s.page, 4);
    });
  });

  test('finishing a later chapter moves read-through on; an earlier one does not', () {
    const t = MemberTitle(mangaId: 1, title: 'X', readThrough: 10, readCount: 10);
    expect(t.finished(11).readThrough, 11);
    expect(t.finished(11).readCount, 11);
    expect(t.finished(4).readThrough, 10);
  });

  group('SuwayomiBackend as a friend', () {
    late DioAdapter adapter;
    late SuwayomiBackend backend;

    setUp(() {
      final dio = Dio(BaseOptions(baseUrl: 'https://gw.test'));
      adapter = DioAdapter(dio: dio);
      dio.httpClientAdapter = adapter;
      backend = SuwayomiBackend(
        config: const ServerConfig(
            id: 'm', name: 'Shaddai Manga', type: ServerType.suwayomi,
            baseUrl: 'https://gw.test', username: 'friend'),
        password: 'pw',
        dio: dio,
      );
      adapter.onGet('/shaddai/me', (s) => s.reply(200, {'role': 'member'}));
      adapter.onGet('/shaddai/library', (s) => s.reply(200, {
            'titles': [
              {'mangaId': 7, 'title': 'Mount Hua', 'categories': ['Murim'], 'readThrough': 2.0, 'readCount': 2},
            ],
          }));
    });

    test('the library and its categories are the friend\'s own', () async {
      adapter.onPost('/api/graphql', (s) => s.reply(200, {
            'data': {
              'mangas': {
                'nodes': [
                  // The owner's unreadCount (0) must not show through.
                  {'id': 7, 'title': 'Mount Hua', 'inLibrary': false, 'unreadCount': 0,
                    'chapters': {'totalCount': 5}, 'meta': []},
                ],
              },
            },
          }), data: Matchers.any);
      expect(await backend.isMember, isTrue);
      final libs = await backend.listLibraries();
      expect(libs.map((l) => l.name), ['Murim']);
      final series = (await backend.listSeries()).items.single;
      expect(series.booksReadCount, 2);
      expect(series.booksUnreadCount, 3);
    });

    test('chapters are read by the friend\'s read-through and records', () async {
      adapter.onPost('/api/graphql', (s) => s.reply(200, {
            'data': {
              'manga': {
                'chapters': {
                  'nodes': [
                    for (final n in [1, 2, 3])
                      {'id': 100 + n, 'name': 'Ch $n', 'chapterNumber': n, 'pageCount': 10,
                        'lastPageRead': 9, 'isRead': true, 'mangaId': 7, 'sourceOrder': n},
                  ],
                },
              },
            },
          }), data: Matchers.any);
      adapter.onGet('/shaddai/progress', (s) => s.reply(200, {
            'chapters': {
              '103': {'chapterId': 103, 'mangaId': 7, 'page': 4, 'read': false},
            },
          }), queryParameters: {'manga_ids': '7'});
      final books = await backend.listBooks('7');
      expect(books.map((b) => b.completed), [true, true, false]);
      expect(books.last.readProgressPage, 4);
      // Owner's page (9) on chapter 1 doesn't leak through either.
      expect(books.first.readProgressPage, isNull);
    });
  });

  test('a server with no /shaddai route is the owner\'s own library', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://owner.test'));
    final adapter = DioAdapter(dio: dio);
    dio.httpClientAdapter = adapter;
    adapter.onGet('/shaddai/me', (s) => s.reply(404, 'not found'));
    final backend = SuwayomiBackend(
      config: const ServerConfig(
          id: 'o', name: 'Suwayomi', type: ServerType.suwayomi,
          baseUrl: 'http://owner.test', username: ''),
      password: '',
      dio: dio,
    );
    expect(await backend.isMember, isFalse);
  });
}
