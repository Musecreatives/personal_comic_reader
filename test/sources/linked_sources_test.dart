import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shaddai_reader/backends/suwayomi/suwayomi_backend.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';
import 'package:shaddai_reader/core/reader/page_cache.dart';
import 'package:shaddai_reader/core/sources/linked_sources.dart';

/// Fails (or hangs) the first [badCalls] page requests, then serves bytes.
class _FlakyBackend implements ReaderBackend {
  _FlakyBackend({required this.badCalls, this.hang = false});
  final int badCalls;
  final bool hang;
  int calls = 0;

  @override
  ServerConfig get config => const ServerConfig(
      id: 's', name: 'S', type: ServerType.suwayomi, baseUrl: 'http://s', username: '');

  @override
  Future<Uint8List> fetchPage(String bookId, int pageIndex) {
    calls++;
    if (calls <= badCalls) {
      return hang ? Completer<Uint8List>().future : Future.error(Exception('503'));
    }
    return Future.value(Uint8List.fromList([1, 2, 3]));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('parseLinkedIds', () {
    test('reads a JSON list of ids, tolerating strings and junk', () {
      expect(parseLinkedIds('[12, "34", "x", null]'), [12, 34]);
      expect(parseLinkedIds(null), isEmpty);
      expect(parseLinkedIds('not json'), isEmpty);
      expect(parseLinkedIds('{"a": 1}'), isEmpty);
    });
  });

  group('matchChapterId', () {
    final byNumber = {1.0: 101, 10.5: 105, 161.0: 161};
    test('matches whole and decimal numbers whatever their spelling', () {
      expect(matchChapterId(byNumber, '161'), 161);
      expect(matchChapterId(byNumber, '161.0'), 161);
      expect(matchChapterId(byNumber, '10.5'), 105);
    });
    test('never matches a missing or unnumbered chapter', () {
      expect(matchChapterId(byNumber, '2'), isNull);
      expect(matchChapterId({-1.0: 9}, '-1'), isNull);
      expect(matchChapterId(byNumber, ''), isNull);
    });
  });

  group('findFallbackChapter', () {
    test('takes the first source in order that has the chapter', () async {
      final asked = <int>[];
      final hit = await findFallbackChapter([1, 2, 3], '10.5', (id) async {
        asked.add(id);
        return switch (id) {
          1 => {10.0: 11},
          2 => {10.5: 22},
          _ => {10.5: 33},
        };
      });
      expect(hit, (mangaId: 2, chapterId: 22));
      expect(asked, [1, 2]); // stops at the first match
    });

    test('skips a source that fails and returns null when none has it', () async {
      final hit = await findFallbackChapter([1, 2], '5', (id) async {
        if (id == 1) throw Exception('site down');
        return {5.0: 55};
      });
      expect(hit, (mangaId: 2, chapterId: 55));
      expect(await findFallbackChapter([1], '5', (_) async => {}), isNull);
      expect(await findFallbackChapter(const [], '5', (_) async => {5.0: 1}), isNull);
    });
  });

  group('mapFallbackPage', () {
    test('carries the position as a fraction and keeps the last page last', () {
      expect(mapFallbackPage(0, 10, 20), 1);
      expect(mapFallbackPage(4, 10, 20), 9);
      expect(mapFallbackPage(9, 10, 20), 19);
      expect(mapFallbackPage(19, 20, 10), 9);
      expect(mapFallbackPage(0, 20, 10), 0);
    });
    test('passes the page through when a count is unknown', () {
      expect(mapFallbackPage(3, 0, 10), 3);
      expect(mapFallbackPage(3, 10, 0), 3);
    });
  });

  group('PageCache page loads', () {
    setUp(setUpTestHive);
    tearDown(tearDownTestHive);

    Future<PageCache> cache() async {
      final c = PageCache(pageTimeout: const Duration(milliseconds: 50));
      await c.init();
      return c;
    }

    test('a request that hangs times out and the retry succeeds', () async {
      final backend = _FlakyBackend(badCalls: 1, hang: true);
      final bytes = await (await cache()).getPage(backend, 'b', 0);
      expect(bytes, [1, 2, 3]);
      expect(backend.calls, 2);
    });

    test('two failures throw and report the page', () async {
      final c = await cache();
      final reported = <({String bookId, int pageIndex})>[];
      c.failures.listen(reported.add);
      final backend = _FlakyBackend(badCalls: 2);
      await expectLater(c.getPage(backend, 'b', 4), throwsException);
      await Future<void>.delayed(Duration.zero);
      expect(reported, [(bookId: 'b', pageIndex: 4)]);
      expect(backend.calls, 2);
    });
  });

  test('SuwayomiBackend reads backups from the shaddai.linkedSources meta', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    final adapter = DioAdapter(dio: dio);
    dio.httpClientAdapter = adapter;
    final backend = SuwayomiBackend(
      config: const ServerConfig(
          id: 's1', name: 'S', type: ServerType.suwayomi, baseUrl: 'http://test.local', username: ''),
      password: '',
      dio: dio,
    );
    adapter.onPost(
      '/api/graphql',
      (server) => server.reply(200, {
        'data': {
          'manga': {
            'meta': [
              {'key': 'other.client', 'value': '[1]'},
              {'key': linkedSourcesMetaKey, 'value': '[42, 7]'},
            ],
          },
        },
      }),
      data: Matchers.any,
    );
    expect(await backend.linkedSourceIds('5'), [42, 7]);
  });
}
