import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../backend/reader_backend.dart';
import '../comicvine/comicvine_key_store.dart';
import '../kapowarr/kapowarr_config.dart';
import '../kapowarr/kapowarr_config_store.dart';
import '../media_pool/media_pool_config.dart';
import '../media_pool/media_pool_config_store.dart';
import '../storage/server_store.dart';
import 'resource_sync.dart';

/// Syncs every connection the user has set up - reading servers (with
/// their passwords), Kapowarr, ComicVine and the media pool - through their
/// sync account, so a fresh install or another device reconnects on sign-in.
///
/// Records are keyed by what names a connection on every device
/// (`server|<portableKey>`, `kapowarr`, ...), never by local server ids:
/// those are random per install, and each device's downloads and history
/// point at its own.
///
/// The stores stay the source of truth for the app; this keeps a mirror box
/// (the synced records) and moves changes between the two. The mirror holds
/// secrets, so it's Hive-AES encrypted with a key kept in secure storage.
/// ponytail: secrets are plain JSON inside the sync DB itself - fine on the
/// owner's server over Tailscale/HTTPS; encrypt client-side before other
/// people's credentials live there.
class ConnectionsSync {
  static const _boxName = 'connections';
  static const _cipherKey = 'connections_box_key';
  static const _serverPrefix = 'server|';
  static const _kapowarr = 'kapowarr';
  static const _comicVine = 'comicvine';
  static const _mediaPool = 'media_pool';

  final ServerStore servers;
  final KapowarrConfigStore kapowarr;
  final ComicVineKeyStore comicVine;
  final MediaPoolConfigStore mediaPool;
  final FlutterSecureStorage _secure;
  final sync = ResourceSync('connections');

  late final Box<String> _box;

  /// True while remote changes are being written into the stores, so their
  /// change callbacks don't echo them straight back as local edits.
  bool _applying = false;

  ConnectionsSync({
    required this.servers,
    required this.kapowarr,
    required this.comicVine,
    required this.mediaPool,
    FlutterSecureStorage? secureStorage,
  }) : _secure = secureStorage ?? const FlutterSecureStorage();

  Future<void> init() async {
    var key = await _secure.read(key: _cipherKey);
    if (key == null) {
      key = base64Encode(Hive.generateSecureKey());
      await _secure.write(key: _cipherKey, value: key);
    }
    _box = await Hive.openBox<String>(
      _boxName,
      encryptionCipher: HiveAesCipher(base64Decode(key)),
    );
    void onLocalChange() {
      if (!_applying) pushLocal();
    }

    servers.onChanged = onLocalChange;
    kapowarr.onChanged = onLocalChange;
    comicVine.onChanged = onLocalChange;
    mediaPool.onChanged = onLocalChange;
  }

  /// Pulls remote changes into the stores, then uploads anything only this
  /// device has. True when a store changed, so the caller can refresh.
  Future<bool> reconcile() async {
    final before = _records().keys.toSet();
    final pulled = await sync.reconcile(_box);
    var changed = false;
    if (pulled) {
      final after = _records();
      changed = await _apply(after, before.difference(after.keys.toSet()));
    }
    await pushLocal();
    return changed;
  }

  /// Every synced record, without ResourceSync's `_`-prefixed bookkeeping.
  Map<String, Map<String, dynamic>> _records() => {
        for (final k in _box.keys.cast<String>())
          if (!k.startsWith('_'))
            k: (jsonDecode(_box.get(k)!) as Map<String, dynamic>)..remove('_at'),
      };

  /// What the records should be, read from the stores.
  Future<Map<String, Map<String, dynamic>>> _localRecords() async {
    final out = <String, Map<String, dynamic>>{};
    for (final s in servers.listServers()) {
      out['$_serverPrefix${s.portableKey}'] = {
        'name': s.name,
        'type': s.type.name,
        'baseUrl': s.baseUrl,
        'username': s.username,
        'password': await servers.getPassword(s.id) ?? '',
      };
    }
    final k = await kapowarr.getWithApiKey();
    if (k != null) out[_kapowarr] = {'baseUrl': k.baseUrl, 'apiKey': k.apiKey};
    final cv = await comicVine.get();
    if (cv != null) out[_comicVine] = {'apiKey': cv};
    final mp = await mediaPool.getWithPassword();
    if (mp != null) {
      out[_mediaPool] = {
        'baseUrl': mp.baseUrl,
        'username': mp.username,
        'password': mp.password,
      };
    }
    return out;
  }

  Future<void> _pushing = Future.value();

  /// Makes the synced records match the stores: new or edited connections
  /// are put, removed ones become tombstones. Only records this box already
  /// holds can be removed, so a fresh, unsynced install never wipes the
  /// account's connections. Runs one at a time: a store edit and a
  /// reconcile overlapping would otherwise both see a record missing and
  /// push it twice.
  Future<void> pushLocal() =>
      _pushing = _pushing.catchError((_) {}).then((_) => _pushLocal());

  Future<void> _pushLocal() async {
    final local = await _localRecords();
    final synced = _records();
    for (final e in local.entries) {
      if (jsonEncode(synced[e.key]) != jsonEncode(e.value)) {
        await sync.put(_box, e.key, e.value);
      }
    }
    for (final key in synced.keys) {
      if (!local.containsKey(key)) await sync.remove(_box, key);
    }
  }

  /// Writes pulled records into the stores; [removed] were deleted remotely.
  Future<bool> _apply(
      Map<String, Map<String, dynamic>> records, Set<String> removed) async {
    final local = await _localRecords();
    var changed = false;
    _applying = true;
    try {
      for (final e in records.entries) {
        if (jsonEncode(local[e.key]) == jsonEncode(e.value)) continue;
        await _write(e.key, e.value);
        changed = true;
      }
      for (final key in removed) {
        await _delete(key);
        changed = true;
      }
      if (servers.getActiveServerId() == null) {
        final first = servers.listServers().firstOrNull;
        if (first != null) await servers.setActiveServerId(first.id);
      }
    } finally {
      _applying = false;
    }
    return changed;
  }

  Future<void> _write(String key, Map<String, dynamic> r) async {
    if (key.startsWith(_serverPrefix)) {
      final portableKey = key.substring(_serverPrefix.length);
      final existing = servers
          .listServers()
          .where((s) => s.portableKey == portableKey)
          .firstOrNull;
      final config = ServerConfig(
        // Reuse this device's id for the server so its downloads and
        // history stay attached; a new server gets a fresh one.
        id: existing?.id ?? const Uuid().v4(),
        name: r['name'] as String,
        type: ServerType.values.byName(r['type'] as String),
        baseUrl: r['baseUrl'] as String,
        username: r['username'] as String,
      );
      await servers.saveServer(config, password: r['password'] as String);
    } else if (key == _kapowarr) {
      await kapowarr.save(KapowarrConfig(
          baseUrl: r['baseUrl'] as String, apiKey: r['apiKey'] as String));
    } else if (key == _comicVine) {
      await comicVine.save(r['apiKey'] as String);
    } else if (key == _mediaPool) {
      await mediaPool.save(MediaPoolConfig(
        baseUrl: r['baseUrl'] as String,
        username: r['username'] as String,
        password: r['password'] as String,
      ));
    }
  }

  Future<void> _delete(String key) async {
    if (key.startsWith(_serverPrefix)) {
      final portableKey = key.substring(_serverPrefix.length);
      for (final s in servers.listServers()) {
        if (s.portableKey == portableKey) await servers.deleteServer(s.id);
      }
    } else if (key == _kapowarr) {
      await kapowarr.clear();
    } else if (key == _comicVine) {
      await comicVine.clear();
    } else if (key == _mediaPool) {
      await mediaPool.clear();
    }
  }
}
