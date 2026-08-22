import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../backend/reader_backend.dart';

/// Persists [ServerConfig]s (non-secret fields in Hive, password in secure
/// storage) and tracks which one is active.
///
/// flutter_secure_storage ships a web implementation backed by IndexedDB +
/// the WebCrypto API, so this works unmodified on Flutter web - no
/// shared_preferences fallback needed, satisfying the "web-safe secure
/// storage" requirement from the project context.
class ServerStore {
  static const _boxName = 'servers';
  static const _activeIdKey = 'activeServerId';

  final FlutterSecureStorage _secure;
  late final Box<String> _box;

  ServerStore({FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ?? const FlutterSecureStorage();

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  List<ServerConfig> listServers() {
    return _box.keys
        .where((k) => k != _activeIdKey)
        .map((k) => ServerConfig.fromJson(
            jsonDecode(_box.get(k)!) as Map<String, dynamic>))
        .toList();
  }

  ServerConfig? getServer(String id) {
    final raw = _box.get(id);
    if (raw == null) return null;
    return ServerConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveServer(ServerConfig config, {String? password}) async {
    await _box.put(config.id, jsonEncode(config.toJson()));
    if (password != null) {
      await _secure.write(key: _passwordKey(config.id), value: password);
    }
  }

  Future<String?> getPassword(String serverId) {
    return _secure.read(key: _passwordKey(serverId));
  }

  Future<void> deleteServer(String id) async {
    await _box.delete(id);
    await _secure.delete(key: _passwordKey(id));
    if (getActiveServerId() == id) {
      await setActiveServerId(null);
    }
  }

  String? getActiveServerId() => _box.get(_activeIdKey);

  Future<void> setActiveServerId(String? id) async {
    if (id == null) {
      await _box.delete(_activeIdKey);
    } else {
      await _box.put(_activeIdKey, id);
    }
  }

  String _passwordKey(String serverId) => 'server_password_$serverId';
}
