import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/backends/suwayomi/suwayomi_maintenance_client.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';

/// Answers GraphQL calls from [reply] and records what was sent, so tests
/// can check the exact variables. A [reply] that throws becomes a GraphQL
/// error, the way Suwayomi reports a source failing. GETs (page images) go
/// to [image].
class _FakeServer {
  final sent = <Map<String, dynamic>>[];
  final gets = <String>[];
  final Map<String, dynamic> Function(String query, Map<String, dynamic> vars) reply;
  final int imageStatus;
  _FakeServer(this.reply, {this.imageStatus = 200});

  Dio dio() {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.method == 'GET') {
        gets.add(options.path);
        final res = Response<dynamic>(
          requestOptions: options,
          statusCode: imageStatus,
          data: imageStatus == 200 ? [1, 2, 3] : 'IOException',
        );
        if (imageStatus == 200) return handler.resolve(res);
        return handler.reject(DioException.badResponse(
            statusCode: imageStatus, requestOptions: options, response: res));
      }
      final body = options.data as Map<String, dynamic>;
      sent.add(body);
      final vars = (body['variables'] as Map<String, dynamic>?) ?? const {};
      Map<String, dynamic> data;
      try {
        data = {'data': reply(body['query'] as String, vars)};
      } catch (e) {
        data = {
          'errors': [
            {'message': '$e'},
          ],
        };
      }
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: data));
    }));
    return dio;
  }
}

const _config = ServerConfig(
  id: 's1',
  name: 'Suwayomi',
  type: ServerType.suwayomi,
  baseUrl: 'http://test.local',
  username: '',
);

SuwayomiMaintenanceClient _client(_FakeServer fake) =>
    SuwayomiMaintenanceClient(config: _config, dio: fake.dio());

void main() {
  group('repo URLs', () {
    test('accepts an https index and trims it', () {
      expect(
        SuwayomiMaintenanceClient.parseRepoUrl(
            '  https://github.com/keiyoushi/extensions/raw/repo/index.pb '),
        'https://github.com/keiyoushi/extensions/raw/repo/index.pb',
      );
    });

    test('rejects http, blanks and non-URLs', () {
      for (final bad in [
        '',
        '   ',
        'http://example.com/index.min.json',
        'not a url',
        'https://',
      ]) {
        expect(() => SuwayomiMaintenanceClient.parseRepoUrl(bad),
            throwsA(isA<FormatException>()),
            reason: bad);
      }
    });
  });

  test('extensionRepos() lists name, index URL and signing key', () async {
    final fake = _FakeServer((q, v) => {
          'extensionStores': {
            'nodes': [
              {
                'name': 'Keiyoushi',
                'indexUrl': 'https://k.test/index.pb',
                'signingKey': '9add655a',
                'isLegacy': false,
              },
            ],
          },
        });
    final repos = await _client(fake).extensionRepos();
    expect(repos.single.name, 'Keiyoushi');
    expect(repos.single.indexUrl, 'https://k.test/index.pb');
    expect(repos.single.signingKey, '9add655a');
  });

  test('addExtensionRepo() validates, then sends the trimmed URL', () async {
    final fake = _FakeServer((q, v) => {
          'addExtensionStore': {
            'extensionStore': {'name': 'Yuzono'},
          },
        });
    final name =
        await _client(fake).addExtensionRepo(' https://y.test/index.min.json ');
    expect(name, 'Yuzono');
    expect(fake.sent.single['variables'], {'url': 'https://y.test/index.min.json'});

    await expectLater(_client(fake).addExtensionRepo('http://y.test/i.json'),
        throwsA(isA<FormatException>()));
    expect(fake.sent, hasLength(1),
        reason: 'an invalid URL never reaches the server');
  });

  test('removeExtensionRepo() sends the index URL', () async {
    final fake = _FakeServer((q, v) => {
          'removeExtensionStore': {'extensionStore': null},
        });
    await _client(fake).removeExtensionRepo('https://y.test/index.min.json');
    expect(fake.sent.single['variables'], {'url': 'https://y.test/index.min.json'});
  });

  test('extensions() refreshes the catalog and maps every field', () async {
    final fake = _FakeServer((q, v) => {
          'fetchExtensions': {
            'extensions': [
              {
                'pkgName': 'eu.kanade.tachiyomi.extension.en.mangabat',
                'name': 'Mangabat',
                'versionName': '1.6.24',
                'lang': 'en',
                'iconUrl': '/api/v1/extension/icon/mangabat',
                'isInstalled': true,
                'hasUpdate': true,
                'isObsolete': false,
                'extensionStore': {'name': 'Keiyoushi'},
                'source': {
                  'nodes': [
                    {'id': '4215511432986138970'},
                  ],
                },
              },
              {
                'pkgName': 'eu.kanade.tachiyomi.extension.en.gone',
                'name': 'Gone',
                'versionName': '1.0',
                'lang': 'en',
                'iconUrl': '',
                'isInstalled': false,
                'hasUpdate': false,
                'isObsolete': true,
                'extensionStore': null,
                'source': {'nodes': []},
              },
            ],
          },
        });
    final list = await _client(fake).extensions();
    expect(fake.sent.single['query'], contains('fetchExtensions'));

    final bat = list.first;
    expect(bat.name, 'Mangabat');
    expect(bat.versionName, '1.6.24');
    expect(bat.lang, 'en');
    expect(bat.isInstalled, isTrue);
    expect(bat.hasUpdate, isTrue);
    expect(bat.repoName, 'Keiyoushi');
    expect(bat.iconUrl, 'http://test.local/api/v1/extension/icon/mangabat');
    expect(bat.sourceIds, ['4215511432986138970']);

    expect(list.last.isObsolete, isTrue);
    expect(list.last.repoName, isNull);
    expect(list.last.iconUrl, isNull);
    expect(list.last.sourceIds, isEmpty);
  });

  group('extension actions send the matching patch', () {
    Future<Map<String, dynamic>> patchFor(
        Future<void> Function(SuwayomiMaintenanceClient c) act) async {
      final fake = _FakeServer((q, v) => {
            'updateExtension': {
              'extension': {'pkgName': v['id']},
            },
            'updateExtensions': {'extensions': []},
          });
      await act(_client(fake));
      return fake.sent.single['variables'] as Map<String, dynamic>;
    }

    test('install', () async {
      expect(await patchFor((c) => c.installExtension('p')), {
        'id': 'p',
        'patch': {'install': true},
      });
    });
    test('update', () async {
      expect(await patchFor((c) => c.updateExtension('p')), {
        'id': 'p',
        'patch': {'update': true},
      });
    });
    test('uninstall', () async {
      expect(await patchFor((c) => c.uninstallExtension('p')), {
        'id': 'p',
        'patch': {'uninstall': true},
      });
    });
    test('update all', () async {
      expect(await patchFor((c) => c.updateExtensions(['a', 'b'])), {
        'ids': ['a', 'b'],
        'patch': {'update': true},
      });
    });
  });

  test('installExtension() names a stale on-disk copy', () async {
    final fake = _FakeServer(
        (q, v) => throw Exception('java.nio.file.FileAlreadyExistsException: x.jar'));
    await expectLater(_client(fake).installExtension('p'),
        throwsA(isA<StaleExtensionFileException>()));
  });

  test('sourceDetails() parses every preference type with its position',
      () async {
    final fake = _FakeServer((q, v) => {
          'source': {
            'id': '42',
            'name': 'Mangabat',
            'displayName': 'Mangabat (EN)',
            'lang': 'en',
            'iconUrl': '/api/v1/extension/icon/mangabat',
            'homeUrl': 'https://www.mangabats.com',
            'supportsLatest': true,
            'isConfigurable': true,
            'contentWarning': 'MIXED',
            'extension': {
              'pkgName': 'eu.kanade.tachiyomi.extension.en.mangabat',
              'versionName': '1.6.24',
              'extensionStore': {'name': 'Keiyoushi'},
            },
            'preferences': [
              {
                '__typename': 'SwitchPreference',
                'key': 'pref_merge_images',
                'title': 'Merge Split Images',
                'summary': null,
                'visible': true,
                'enabled': true,
                'boolValue': false,
                'boolDefault': false,
              },
              {
                '__typename': 'CheckBoxPreference',
                'key': 'cb',
                'title': 'Check',
                'summary': 'Desc',
                'visible': true,
                'enabled': true,
                'boolValue': null,
                'boolDefault': true,
              },
              {
                '__typename': 'ListPreference',
                'key': 'mirror',
                'title': 'Mirror',
                'summary': '%s',
                'visible': true,
                'enabled': true,
                'listValue': 'b',
                'listDefault': 'a',
                'entries': ['Main', 'Backup'],
                'entryValues': ['a', 'b'],
              },
              {
                '__typename': 'MultiSelectListPreference',
                'key': 'langs',
                'title': 'Languages',
                'summary': null,
                'visible': true,
                'enabled': true,
                'multiValue': ['en'],
                'multiDefault': null,
                'entries': ['English', 'French'],
                'entryValues': ['en', 'fr'],
              },
              {
                '__typename': 'EditTextPreference',
                'key': 'ua',
                'title': 'User agent',
                'summary': null,
                'visible': false,
                'enabled': true,
                'textValue': null,
                'textDefault': 'Mozilla',
              },
            ],
          },
        });
    final s = await _client(fake).sourceDetails('42');
    expect(fake.sent.single['variables'], {'id': '42'});

    expect(s.id, '42');
    expect(s.name, 'Mangabat');
    expect(s.lang, 'en');
    expect(s.homeUrl, 'https://www.mangabats.com');
    expect(s.iconUrl, 'http://test.local/api/v1/extension/icon/mangabat');
    expect(s.supportsLatest, isTrue);
    expect(s.rating, ContentRating.mixed);
    expect(s.pkgName, 'eu.kanade.tachiyomi.extension.en.mangabat');
    expect(s.versionName, '1.6.24');
    expect(s.repoName, 'Keiyoushi');

    final p = s.preferences;
    expect(p.map((e) => e.position), [0, 1, 2, 3, 4]);
    expect((p[0] as BoolPreference).value, isFalse);
    expect((p[0] as BoolPreference).isCheckBox, isFalse);
    expect((p[1] as BoolPreference).isCheckBox, isTrue);
    expect((p[1] as BoolPreference).value, isTrue,
        reason: 'falls back to the default when unset');
    final list = p[2] as ListPreference;
    expect(list.value, 'b');
    expect(list.selectedLabel, 'Backup');
    final multi = p[3] as MultiSelectPreference;
    expect(multi.values, {'en'});
    final text = p[4] as TextPreference;
    expect(text.value, 'Mozilla');
    expect(text.visible, isFalse);
  });

  test('sourceDetails() reads an adult source without an extension', () async {
    final fake = _FakeServer((q, v) => {
          'source': {
            'id': '9',
            'name': 'nhentai',
            'displayName': 'nhentai',
            'lang': 'all',
            'iconUrl': '',
            'homeUrl': '',
            'supportsLatest': false,
            'isConfigurable': false,
            'contentWarning': 'NSFW',
            'extension': null,
            'preferences': [],
          },
        });
    final s = await _client(fake).sourceDetails('9');
    expect(s.rating, ContentRating.adult);
    expect(s.pkgName, isNull);
    expect(s.homeUrl, isNull);
  });

  test('sources() lists installed sources without the local one', () async {
    final fake = _FakeServer((q, v) => {
          'sources': {
            'nodes': [
              {'id': '0', 'name': 'Local source', 'lang': 'localsourcelang', 'iconUrl': '/i/local', 'contentWarning': 'SAFE'},
              {'id': '4215511432986138970', 'name': 'Mangabat', 'lang': 'en', 'iconUrl': '/i/bat', 'contentWarning': 'MIXED'},
              {'id': '9', 'name': 'nhentai', 'lang': 'all', 'iconUrl': '', 'contentWarning': 'NSFW'},
              {'id': '8', 'name': 'Flame', 'lang': 'en', 'iconUrl': '/i/f', 'contentWarning': 'SAFE'},
              {'id': '7', 'name': 'Own host', 'lang': 'en', 'iconUrl': 'http://test.local/i/o', 'contentWarning': 'SAFE'},
              {'id': '6', 'name': 'Look-alike', 'lang': 'en', 'iconUrl': 'http://test.local.evil.example/i', 'contentWarning': 'SAFE'},
            ],
          },
        });
    final list = await _client(fake).sources();
    expect(list.map((s) => s.id), ['4215511432986138970', '9', '8', '7', '6']);
    expect(list.first.iconUrl, 'http://test.local/i/bat');
    expect(list.first.rating, ContentRating.mixed);
    expect(list[1].rating, ContentRating.adult);
    expect(list[1].iconUrl, isNull);
    expect(list[2].rating, ContentRating.safe);
    // Icons load with the login headers: only the server's own host.
    expect(list[3].iconUrl, 'http://test.local/i/o');
    expect(list[4].iconUrl, isNull);
  });

  test('an unknown content warning reads as mixed, never as safe', () {
    expect(ContentRating.parse('SOMETHING_NEW'), ContentRating.mixed);
    expect(ContentRating.parse(null), ContentRating.mixed);
  });

  group('setSourcePreference() sends the state field for its type', () {
    Future<Map<String, dynamic>> changeFor(SourcePreference pref, Object value) async {
      final fake = _FakeServer((q, v) => {
            'updateSourcePreference': {
              'source': {'id': '42'},
            },
          });
      await _client(fake).setSourcePreference('42', pref, value);
      return fake.sent.single['variables'] as Map<String, dynamic>;
    }

    test('switch', () async {
      const pref = BoolPreference(
          position: 0, key: 'k', title: 'T', summary: null, visible: true,
          enabled: true, value: false);
      expect(await changeFor(pref, true), {
        'source': '42',
        'change': {'position': 0, 'switchState': true},
      });
    });
    test('checkbox', () async {
      const pref = BoolPreference(
          position: 1, key: 'k', title: 'T', summary: null, visible: true,
          enabled: true, value: false, isCheckBox: true);
      expect(await changeFor(pref, true), {
        'source': '42',
        'change': {'position': 1, 'checkBoxState': true},
      });
    });
    test('list', () async {
      const pref = ListPreference(
          position: 2, key: 'k', title: 'T', summary: null, visible: true,
          enabled: true, value: 'a', entries: ['A', 'B'], entryValues: ['a', 'b']);
      expect(await changeFor(pref, 'b'), {
        'source': '42',
        'change': {'position': 2, 'listState': 'b'},
      });
    });
    test('multi-select', () async {
      const pref = MultiSelectPreference(
          position: 3, key: 'k', title: 'T', summary: null, visible: true,
          enabled: true, values: {}, entries: ['A'], entryValues: ['a']);
      expect(await changeFor(pref, {'a'}), {
        'source': '42',
        'change': {
          'position': 3,
          'multiSelectState': ['a'],
        },
      });
    });
    test('text', () async {
      const pref = TextPreference(
          position: 4, key: 'k', title: 'T', summary: null, visible: true,
          enabled: true, value: '');
      expect(await changeFor(pref, 'x'), {
        'source': '42',
        'change': {'position': 4, 'editTextState': 'x'},
      });
    });
  });

  group('checkSource()', () {
    Map<String, dynamic> Function(String, Map<String, dynamic>) server(
        {bool emptyCatalog = false, bool failPages = false}) {
      return (q, v) {
        if (q.contains('fetchSourceManga')) {
          return {
            'fetchSourceManga': {
              'mangas': emptyCatalog
                  ? []
                  : [
                      {'id': 7},
                    ],
            },
          };
        }
        if (q.contains('fetchChapters')) {
          return {
            'fetchChapters': {
              'chapters': [
                {'id': 70, 'sourceOrder': 1},
                {'id': 71, 'sourceOrder': 2},
              ],
            },
          };
        }
        if (q.contains('fetchChapterPages')) {
          if (failPages) throw Exception('All CDN attempts failed.');
          return {
            'fetchChapterPages': {
              'pages': ['/p/0'],
            },
          };
        }
        throw StateError('unexpected $q');
      };
    }

    test('passes when catalog, chapters, page list and an image all load',
        () async {
      final fake = _FakeServer(server());
      final r = await _client(fake).checkSource('42');
      expect(r.ok, isTrue);
      expect(r.steps.map((s) => s.name), ['Catalog', 'Chapters', 'Pages', 'Image']);
      expect(r.steps.every((s) => s.ok), isTrue);
      // The newest chapter (highest sourceOrder), its first page.
      expect(fake.sent.last['variables'], {'id': 71});
      expect(fake.gets.single, '/api/v1/manga/7/chapter/2/page/0');
    });

    test('stops at the first step that fails and says which', () async {
      final r = await _client(_FakeServer(server(emptyCatalog: true)))
          .checkSource('42');
      expect(r.ok, isFalse);
      expect(r.steps.single.name, 'Catalog');
      expect(r.steps.single.error, contains('no titles'));
    });

    test('reports the source error when the page list fails', () async {
      final r =
          await _client(_FakeServer(server(failPages: true))).checkSource('42');
      expect(r.ok, isFalse);
      expect(r.steps.last.name, 'Pages');
      expect(r.steps.last.error, contains('All CDN attempts failed'));
    });

    test('catches an image the source cannot serve', () async {
      final r = await _client(_FakeServer(server(), imageStatus: 500))
          .checkSource('42');
      expect(r.ok, isFalse);
      expect(r.steps.last.name, 'Image');
      expect(r.steps.last.error, contains('500'));
    });
  });
}
