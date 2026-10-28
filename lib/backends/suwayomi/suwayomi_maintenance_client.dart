import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/debug/debug_log.dart';

import '../../core/backend/reader_backend.dart';
import '../../core/network/retry_interceptor.dart';

/// The extensions this library actually uses, keyed by their Suwayomi
/// package name - the exact set installed during the Paperback migration
/// (2026-08-25) plus what's been added since. Not the full remote catalog
/// (hundreds of extensions) - this is specifically "the ones we care
/// about being installed", so the maintenance screen can show a plain
/// X/14 health number instead of an unfiltered wall of every extension
/// Suwayomi's repo knows about.
const knownExtensionPackages = <String, String>{
  'eu.kanade.tachiyomi.extension.all.mangadex': 'MangaDex',
  'eu.kanade.tachiyomi.extension.all.nhentaicom': 'nhentai',
  'eu.kanade.tachiyomi.extension.en.asurascans': 'Asura Scans',
  'eu.kanade.tachiyomi.extension.en.comicasura': 'Comic Asura',
  'eu.kanade.tachiyomi.extension.en.flamecomics': 'Flame Comics',
  'eu.kanade.tachiyomi.extension.en.kissmangain': 'Kissmanga.in',
  'eu.kanade.tachiyomi.extension.en.mangabat': 'Mangabat',
  'eu.kanade.tachiyomi.extension.en.mangakakalot': 'Mangakakalot',
  'eu.kanade.tachiyomi.extension.en.mangakatana': 'MangaKatana',
  'eu.kanade.tachiyomi.extension.en.manganelo': 'Manganato',
  'eu.kanade.tachiyomi.extension.en.manhwabuddy': 'ManhwaBuddy',
  'eu.kanade.tachiyomi.extension.en.readcomicsonline': 'Read Comics Online',
  'eu.kanade.tachiyomi.extension.en.toonilyme': 'Toonily.me',
  'eu.kanade.tachiyomi.extension.tr.asurascanstr': 'Asura Scans (TR)',
};

class ExtensionStatus {
  final String pkgName;
  final String name;
  final bool isInstalled;
  const ExtensionStatus({required this.pkgName, required this.name, required this.isInstalled});
}

class LibraryHealth {
  final int categoryCount;
  final int totalManga;
  const LibraryHealth({required this.categoryCount, required this.totalManga});
}

/// An extension repo (Suwayomi calls them extension stores): an index of
/// Tachiyomi-format extensions, e.g. Keiyoushi's.
class ExtensionRepo {
  final String name;
  final String indexUrl;

  /// Fingerprint of the key the repo signs its extensions with.
  final String? signingKey;
  const ExtensionRepo({required this.name, required this.indexUrl, this.signingKey});
}

/// One extension from the catalog of every configured repo.
class ExtensionInfo {
  final String pkgName;
  final String name;
  final String versionName;
  final String lang;
  final String? iconUrl;
  final bool isInstalled;
  final bool hasUpdate;

  /// Installed, but no repo offers it any more.
  final bool isObsolete;
  final String? repoName;
  final List<String> sourceIds;

  const ExtensionInfo({
    required this.pkgName,
    required this.name,
    required this.versionName,
    required this.lang,
    required this.iconUrl,
    required this.isInstalled,
    required this.hasUpdate,
    required this.isObsolete,
    required this.repoName,
    required this.sourceIds,
  });
}

/// A source's own setting, as its extension declares it. [position] is its
/// index in the source's list, which is how Suwayomi addresses a change.
sealed class SourcePreference {
  final int position;
  final String? key;
  final String? title;
  final String? summary;
  final bool visible;
  final bool enabled;
  const SourcePreference({
    required this.position,
    required this.key,
    required this.title,
    required this.summary,
    required this.visible,
    required this.enabled,
  });
}

/// A switch or a checkbox; they differ only in how Suwayomi takes the change.
class BoolPreference extends SourcePreference {
  final bool value;
  final bool isCheckBox;
  const BoolPreference({
    required super.position,
    required super.key,
    required super.title,
    required super.summary,
    required super.visible,
    required super.enabled,
    required this.value,
    this.isCheckBox = false,
  });
}

class ListPreference extends SourcePreference {
  final String? value;
  final List<String> entries;
  final List<String> entryValues;
  const ListPreference({
    required super.position,
    required super.key,
    required super.title,
    required super.summary,
    required super.visible,
    required super.enabled,
    required this.value,
    required this.entries,
    required this.entryValues,
  });

  /// The label shown for [value], or the raw value if it isn't listed.
  String? get selectedLabel {
    final i = entryValues.indexOf(value ?? '');
    return i >= 0 && i < entries.length ? entries[i] : value;
  }
}

class MultiSelectPreference extends SourcePreference {
  final Set<String> values;
  final List<String> entries;
  final List<String> entryValues;
  const MultiSelectPreference({
    required super.position,
    required super.key,
    required super.title,
    required super.summary,
    required super.visible,
    required super.enabled,
    required this.values,
    required this.entries,
    required this.entryValues,
  });
}

class TextPreference extends SourcePreference {
  final String value;
  const TextPreference({
    required super.position,
    required super.key,
    required super.title,
    required super.summary,
    required super.visible,
    required super.enabled,
    required this.value,
  });
}

/// How much adult content a source carries, from Suwayomi's content
/// warning (SAFE, MIXED, NSFW).
enum ContentRating {
  safe,
  mixed,
  adult;

  /// Anything unrecognised is treated as mixed: never assume safe.
  static ContentRating parse(String? raw) => switch (raw) {
        'SAFE' => safe,
        'NSFW' => adult,
        _ => mixed,
      };
}

/// One installed source, as the sources list shows it.
class SourceSummary {
  final String id;
  final String name;
  final String lang;
  final String? iconUrl;
  final ContentRating rating;
  const SourceSummary({
    required this.id,
    required this.name,
    required this.lang,
    required this.iconUrl,
    required this.rating,
  });
}

/// Everything the source details page shows.
class SourceDetails {
  final String id;
  final String name;
  final String lang;
  final String? iconUrl;
  final String? homeUrl;
  final bool supportsLatest;
  final ContentRating rating;
  final String? pkgName;
  final String? versionName;
  final String? repoName;
  final List<SourcePreference> preferences;

  const SourceDetails({
    required this.id,
    required this.name,
    required this.lang,
    required this.iconUrl,
    required this.homeUrl,
    required this.supportsLatest,
    required this.rating,
    required this.pkgName,
    required this.versionName,
    required this.repoName,
    required this.preferences,
  });
}

/// One stage of [SuwayomiMaintenanceClient.checkSource].
class SourceCheckStep {
  final String name;
  final Duration took;

  /// Null when the step worked.
  final String? error;
  const SourceCheckStep({required this.name, required this.took, this.error});
  bool get ok => error == null;
}

class SourceCheck {
  final List<SourceCheckStep> steps;
  const SourceCheck(this.steps);
  bool get ok => steps.every((s) => s.ok);
}

/// Thrown when reinstalling an extension fails because its old .jar is
/// still sitting on disk from before - Suwayomi's installer won't
/// overwrite it, and deleting server files isn't something this client
/// does on its own (matches the read-only-by-design posture used for
/// Kapowarr's REST client).
class StaleExtensionFileException implements Exception {
  final String pkgName;
  const StaleExtensionFileException(this.pkgName);
  @override
  String toString() =>
      'A previous copy of this extension is still on the server and needs to be '
      'cleared by hand before it can be reinstalled.';
}

/// Suwayomi maintenance operations - extension health/reinstall and
/// backup/restore. Deliberately separate from [SuwayomiBackend] (the
/// `ReaderBackend` implementation used for actually reading): these are
/// admin-only operations that don't belong on the reading-facing
/// interface, mirroring why Kapowarr's read-only client never grew
/// monitor/search actions either.
class SuwayomiMaintenanceClient {
  final Dio _dio;
  final String _baseUrl;

  /// The login headers, for loading extension icons by URL.
  final Map<String, String> imageHeaders;

  /// [headers]: the backend's login headers ([SuwayomiBackend.imageHeaders]).
  SuwayomiMaintenanceClient({
    required ServerConfig config,
    Map<String, String> headers = const {},
    Dio? dio,
  }) : _baseUrl = config.baseUrl,
       imageHeaders = headers,
       _dio = dio ??
            trackedDio(BaseOptions(
              baseUrl: config.baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            )) {
    _dio.options.headers.addAll(headers);
    _dio.interceptors.add(RetryInterceptor(dio: _dio));
  }

  Future<Map<String, dynamic>> _gql(String query, [Map<String, dynamic>? variables]) async {
    final res = await _dio.post('/api/graphql', data: {
      'query': query,
      'variables': ?variables,
    });
    final data = res.data as Map<String, dynamic>;
    if (data['errors'] != null) {
      throw Exception('Suwayomi GraphQL error: ${data['errors']}');
    }
    return data['data'] as Map<String, dynamic>;
  }

  Future<LibraryHealth> libraryHealth() async {
    final data = await _gql('{ categories { nodes { mangas { totalCount } } } }');
    final nodes = (data['categories'] as Map<String, dynamic>)['nodes'] as List;
    final total = nodes.fold<int>(
        0, (sum, n) => sum + ((n as Map<String, dynamic>)['mangas']['totalCount'] as int));
    return LibraryHealth(categoryCount: nodes.length, totalManga: total);
  }

  /// A wiped/replaced database loses the configured extension repo, and
  /// with no repo the catalog comes back empty - so every extension looks
  /// "not installed" and can't be reinstalled (hit on 2026-09-22). Restore
  /// the standard repo the known packages come from whenever it's missing.
  Future<void> _ensureExtensionRepo() async {
    final data = await _gql('{ settings { extensionRepos } }');
    final repos = (data['settings'] as Map<String, dynamic>)['extensionRepos'] as List;
    if (repos.isNotEmpty) return;
    await _gql(
      'mutation(\$repos: [String!]!) { setSettings(input: {settings: {extensionRepos: \$repos}}) { settings { extensionRepos } } }',
      {
        'repos': ['https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json'],
      },
    );
  }

  /// Installs every known extension that isn't installed yet. Returns the
  /// package names that couldn't be installed because of a stale on-disk
  /// copy (those need clearing on the server); other failures propagate.
  Future<List<String>> reinstallAllMissing() async {
    final stale = <String>[];
    for (final ext in await extensionStatus()) {
      if (ext.isInstalled) continue;
      try {
        await installExtension(ext.pkgName);
      } on StaleExtensionFileException {
        stale.add(ext.pkgName);
      }
    }
    return stale;
  }

  /// Fetches the remote extension catalog and reports install state for
  /// [knownExtensionPackages] only.
  Future<List<ExtensionStatus>> extensionStatus() async {
    await _ensureExtensionRepo();
    final data = await _gql(
        'mutation { fetchExtensions(input: {}) { extensions { pkgName isInstalled } } }');
    final nodes =
        (data['fetchExtensions'] as Map<String, dynamic>)['extensions'] as List;
    final installed = <String, bool>{
      for (final n in nodes)
        (n as Map<String, dynamic>)['pkgName'] as String: n['isInstalled'] as bool,
    };
    return knownExtensionPackages.entries
        .map((e) => ExtensionStatus(
              pkgName: e.key,
              name: e.value,
              isInstalled: installed[e.key] ?? false,
            ))
        .toList();
  }

  Future<void> installExtension(String pkgName) async {
    try {
      await _patchExtension(pkgName, 'install');
    } catch (e) {
      if (e.toString().contains('FileAlreadyExistsException')) {
        throw StaleExtensionFileException(pkgName);
      }
      rethrow;
    }
  }

  Future<void> updateExtension(String pkgName) => _patchExtension(pkgName, 'update');

  Future<void> uninstallExtension(String pkgName) =>
      _patchExtension(pkgName, 'uninstall');

  Future<void> updateExtensions(List<String> pkgNames) => _gql(
        'mutation(\$ids: [String!]!, \$patch: UpdateExtensionPatchInput!) { '
        'updateExtensions(input: {ids: \$ids, patch: \$patch}) { extensions { pkgName } } }',
        {
          'ids': pkgNames,
          'patch': {'update': true},
        },
      );

  Future<void> _patchExtension(String pkgName, String action) => _gql(
        'mutation(\$id: String!, \$patch: UpdateExtensionPatchInput!) { '
        'updateExtension(input: {id: \$id, patch: \$patch}) { extension { pkgName } } }',
        {
          'id': pkgName,
          'patch': {action: true},
        },
      );

  /// A repo index URL as typed, made safe to send: trimmed, https only (a
  /// repo is code the server will run), with a host. Throws a
  /// [FormatException] whose message can be shown as is.
  static String parseRepoUrl(String raw) {
    final url = raw.trim();
    final uri = Uri.tryParse(url);
    if (url.isEmpty || uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException("That isn't a web address.");
    }
    if (uri.scheme != 'https') {
      throw const FormatException('Repos must use https://');
    }
    return url;
  }

  Future<List<ExtensionRepo>> extensionRepos() async {
    final data = await _gql('{ extensionStores { nodes { name indexUrl signingKey } } }');
    return [
      for (final n in data['extensionStores']['nodes'] as List)
        ExtensionRepo(
          name: n['name'] as String? ?? '',
          indexUrl: n['indexUrl'] as String,
          signingKey: n['signingKey'] as String?,
        ),
    ];
  }

  /// Adds a repo and returns the name it reports.
  Future<String> addExtensionRepo(String url) async {
    final data = await _gql(
      'mutation(\$url: String!) { addExtensionStore(input: {indexUrl: \$url}) { extensionStore { name } } }',
      {'url': parseRepoUrl(url)},
    );
    return data['addExtensionStore']['extensionStore']['name'] as String? ?? '';
  }

  Future<void> removeExtensionRepo(String url) => _gql(
        'mutation(\$url: String!) { removeExtensionStore(input: {indexUrl: \$url}) { extensionStore { name } } }',
        {'url': url},
      );

  /// Every extension every repo offers, plus installed ones no repo has
  /// any more, after asking the repos for their current catalog.
  Future<List<ExtensionInfo>> extensions() async {
    final data = await _gql(
      'mutation { fetchExtensions(input: {}) { extensions { pkgName name versionName lang '
      'iconUrl isInstalled hasUpdate isObsolete extensionStore { name } source { nodes { id } } } } }',
    );
    return [
      for (final e in data['fetchExtensions']['extensions'] as List)
        ExtensionInfo(
          pkgName: e['pkgName'] as String,
          name: e['name'] as String? ?? '',
          versionName: e['versionName'] as String? ?? '',
          lang: e['lang'] as String? ?? '',
          iconUrl: _absolute(e['iconUrl'] as String?),
          isInstalled: e['isInstalled'] as bool? ?? false,
          hasUpdate: e['hasUpdate'] as bool? ?? false,
          isObsolete: e['isObsolete'] as bool? ?? false,
          repoName: (e['extensionStore'] as Map<String, dynamic>?)?['name'] as String?,
          sourceIds: [
            for (final s in (e['source']?['nodes'] as List? ?? const [])) '${s['id']}',
          ],
        ),
    ];
  }

  /// Icons load with [imageHeaders], so an absolute URL on another host
  /// (a repo pointing icons elsewhere) is dropped rather than handed the
  /// login. Suwayomi itself serves icons as relative paths.
  String? _absolute(String? path) {
    if (path == null || path.isEmpty) return null;
    if (!path.startsWith('http')) return '$_baseUrl$path';
    final url = Uri.tryParse(path);
    return url != null && url.origin == Uri.parse(_baseUrl).origin ? path : null;
  }

  /// Every installed source except Suwayomi's local folder (id 0).
  Future<List<SourceSummary>> sources() async {
    final data = await _gql('{ sources { nodes { id name lang iconUrl contentWarning } } }');
    return [
      for (final s in data['sources']['nodes'] as List)
        if ('${s['id']}' != '0')
          SourceSummary(
            id: '${s['id']}',
            name: s['name'] as String? ?? '',
            lang: s['lang'] as String? ?? '',
            iconUrl: _absolute(s['iconUrl'] as String?),
            rating: ContentRating.parse(s['contentWarning'] as String?),
          ),
    ];
  }

  static const _preferenceFields =
      '__typename '
      '... on SwitchPreference { key title summary visible enabled boolValue: currentValue boolDefault: default } '
      '... on CheckBoxPreference { key title summary visible enabled boolValue: currentValue boolDefault: default } '
      '... on ListPreference { key title summary visible enabled listValue: currentValue listDefault: default entries entryValues } '
      '... on MultiSelectListPreference { key title summary visible enabled multiValue: currentValue multiDefault: default entries entryValues } '
      '... on EditTextPreference { key title summary visible enabled textValue: currentValue textDefault: default }';

  Future<SourceDetails> sourceDetails(String sourceId) async {
    final data = await _gql(
      'query(\$id: LongString!) { source(id: \$id) { id name lang iconUrl homeUrl '
      'supportsLatest contentWarning extension { pkgName versionName extensionStore { name } } '
      'preferences { $_preferenceFields } } }',
      {'id': sourceId},
    );
    final s = data['source'] as Map<String, dynamic>;
    final ext = s['extension'] as Map<String, dynamic>?;
    final home = s['homeUrl'] as String?;
    final prefs = s['preferences'] as List;
    return SourceDetails(
      id: '${s['id']}',
      name: s['name'] as String? ?? '',
      lang: s['lang'] as String? ?? '',
      iconUrl: _absolute(s['iconUrl'] as String?),
      homeUrl: home == null || home.isEmpty ? null : home,
      supportsLatest: s['supportsLatest'] as bool? ?? false,
      rating: ContentRating.parse(s['contentWarning'] as String?),
      pkgName: ext?['pkgName'] as String?,
      versionName: ext?['versionName'] as String?,
      repoName: (ext?['extensionStore'] as Map<String, dynamic>?)?['name'] as String?,
      preferences: [
        for (var i = 0; i < prefs.length; i++)
          ?_preference(i, prefs[i] as Map<String, dynamic>),
      ],
    );
  }

  static SourcePreference? _preference(int i, Map<String, dynamic> p) {
    final key = p['key'] as String?;
    final title = p['title'] as String?;
    final summary = p['summary'] as String?;
    final visible = p['visible'] as bool? ?? true;
    final enabled = p['enabled'] as bool? ?? true;
    List<String> strings(Object? v) => [for (final x in (v as List? ?? const [])) '$x'];
    return switch (p['__typename']) {
      'SwitchPreference' || 'CheckBoxPreference' => BoolPreference(
          position: i, key: key, title: title, summary: summary,
          visible: visible, enabled: enabled,
          value: p['boolValue'] as bool? ?? p['boolDefault'] as bool? ?? false,
          isCheckBox: p['__typename'] == 'CheckBoxPreference',
        ),
      'ListPreference' => ListPreference(
          position: i, key: key, title: title, summary: summary,
          visible: visible, enabled: enabled,
          value: p['listValue'] as String? ?? p['listDefault'] as String?,
          entries: strings(p['entries']),
          entryValues: strings(p['entryValues']),
        ),
      'MultiSelectListPreference' => MultiSelectPreference(
          position: i, key: key, title: title, summary: summary,
          visible: visible, enabled: enabled,
          values: strings(p['multiValue'] ?? p['multiDefault']).toSet(),
          entries: strings(p['entries']),
          entryValues: strings(p['entryValues']),
        ),
      'EditTextPreference' => TextPreference(
          position: i, key: key, title: title, summary: summary,
          visible: visible, enabled: enabled,
          value: p['textValue'] as String? ?? p['textDefault'] as String? ?? '',
        ),
      // A type a newer Suwayomi adds: skip it rather than break the page.
      _ => null,
    };
  }

  /// Saves one source setting. [value] is a `bool`, a `String` or a `Set<String>`
  /// to match [pref]'s type.
  Future<void> setSourcePreference(
      String sourceId, SourcePreference pref, Object value) {
    final change = <String, Object>{
      'position': pref.position,
      ...switch (pref) {
        BoolPreference(isCheckBox: true) => {'checkBoxState': value as bool},
        BoolPreference() => {'switchState': value as bool},
        ListPreference() => {'listState': value as String},
        MultiSelectPreference() => {'multiSelectState': (value as Set<String>).toList()},
        TextPreference() => {'editTextState': value as String},
      },
    };
    return _gql(
      'mutation(\$source: LongString!, \$change: SourcePreferenceChangeInput!) { '
      'updateSourcePreference(input: {source: \$source, change: \$change}) { source { id } } }',
      {'source': sourceId, 'change': change},
    );
  }

  /// Reads a source the way the reader does - its popular list, the first
  /// title's chapters, the newest chapter's page list, then that chapter's
  /// first image - and reports how long each step took, stopping at the
  /// first that fails. The image step matters: Mangabat's page lists load
  /// while its image server refuses files.
  Future<SourceCheck> checkSource(String sourceId) async {
    final steps = <SourceCheckStep>[];
    Future<T?> step<T>(String name, Future<T> Function() run) async {
      final watch = Stopwatch()..start();
      try {
        final result = await run();
        steps.add(SourceCheckStep(name: name, took: watch.elapsed));
        return result;
      } catch (e) {
        steps.add(SourceCheckStep(name: name, took: watch.elapsed, error: _plain(e)));
        return null;
      }
    }

    final mangaId = await step('Catalog', () async {
      final data = await _gql(
        'mutation(\$source: LongString!) { fetchSourceManga(input: {source: \$source, '
        'type: POPULAR, page: 1, filters: []}) { mangas { id } } }',
        {'source': sourceId},
      );
      final mangas = data['fetchSourceManga']['mangas'] as List;
      if (mangas.isEmpty) throw const FormatException('The source listed no titles.');
      return mangas.first['id'] as int;
    });
    if (mangaId == null) return SourceCheck(steps);

    final chapter = await step('Chapters', () async {
      final data = await _gql(
        'mutation(\$id: Int!) { fetchChapters(input: {mangaId: \$id}) { chapters { id sourceOrder } } }',
        {'id': mangaId},
      );
      final chapters = data['fetchChapters']['chapters'] as List;
      if (chapters.isEmpty) throw const FormatException('The title has no chapters.');
      // Newest = highest sourceOrder.
      var newest = (id: -1, order: -1);
      for (final c in chapters) {
        final order = c['sourceOrder'] as int;
        if (order > newest.order) newest = (id: c['id'] as int, order: order);
      }
      return newest;
    });
    if (chapter == null) return SourceCheck(steps);

    final pages = await step('Pages', () async {
      final data = await _gql(
        'mutation(\$id: Int!) { fetchChapterPages(input: {chapterId: \$id}) { pages } }',
        {'id': chapter.id},
      );
      final pages = data['fetchChapterPages']['pages'] as List;
      if (pages.isEmpty) throw const FormatException('The chapter has no pages.');
      return pages.length;
    });
    if (pages == null) return SourceCheck(steps);

    await step('Image', () => _dio.get<List<int>>(
          '/api/v1/manga/$mangaId/chapter/${chapter.order}/page/0',
          options: Options(responseType: ResponseType.bytes),
        ));
    return SourceCheck(steps);
  }

  /// An error as one readable line: the server's own words where there are
  /// some, not Dio's wrapping.
  static String _plain(Object e) {
    if (e is FormatException) return e.message;
    if (e is DioException) {
      final code = e.response?.statusCode;
      return code == null ? (e.message ?? 'No answer from the server.') : 'HTTP $code';
    }
    return '$e'.replaceFirst('Exception: ', '');
  }

  /// Triggers a fresh backup on the server and returns its download URL.
  Future<String> createBackup() async {
    final data = await _gql('mutation { createBackup(input: {}) { url } }');
    return (data['createBackup'] as Map<String, dynamic>)['url'] as String;
  }

  /// Uploads [bytes] as a `.tachibk` backup and restores it - this
  /// REPLACES the current library. Returns once Suwayomi reports the
  /// restore finished (polls `restoreStatus`).
  Future<void> restoreBackup(Uint8List bytes, {required String filename}) async {
    final form = FormData.fromMap({
      'operations': jsonEncodeOperations(),
      'map': '{"0":["variables.backup"]}',
      '0': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res = await _dio.post('/api/graphql', data: form);
    final data = res.data as Map<String, dynamic>;
    if (data['errors'] != null) {
      throw Exception('Suwayomi restore error: ${data['errors']}');
    }
    final id = (data['data']['restoreBackup'] as Map<String, dynamic>)['id'] as String;

    // Poll until the restore actually finishes - it reports SUCCESS
    // asynchronously, same as when this was done by hand.
    for (var i = 0; i < 60; i++) {
      await Future.delayed(const Duration(seconds: 1));
      final status = await _gql(
        'query(\$id: String!) { restoreStatus(id: \$id) { state } }',
        {'id': id},
      );
      final state = (status['restoreStatus'] as Map<String, dynamic>)['state'] as String;
      if (state == 'SUCCESS') return;
      if (state == 'FAILURE') throw Exception('Suwayomi reported the restore failed.');
    }
    throw Exception('Restore is taking longer than expected - check Suwayomi directly.');
  }

  String jsonEncodeOperations() =>
      '{"query":"mutation(\$backup: Upload!){ restoreBackup(input:{backup:\$backup}){ id status { state } } }","variables":{"backup":null}}';
}
