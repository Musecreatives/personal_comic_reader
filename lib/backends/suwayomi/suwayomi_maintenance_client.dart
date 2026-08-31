import 'dart:typed_data';

import 'package:dio/dio.dart';

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

  SuwayomiMaintenanceClient({required ServerConfig config, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: config.baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            )) {
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

  /// Fetches the remote extension catalog and reports install state for
  /// [knownExtensionPackages] only.
  Future<List<ExtensionStatus>> extensionStatus() async {
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

  Future<void> reinstallExtension(String pkgName) async {
    try {
      await _gql(
        'mutation(\$id: String!) { updateExtension(input: {id: \$id, patch: {install: true}}) { extension { pkgName } } }',
        {'id': pkgName},
      );
    } catch (e) {
      if (e.toString().contains('FileAlreadyExistsException')) {
        throw StaleExtensionFileException(pkgName);
      }
      rethrow;
    }
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
