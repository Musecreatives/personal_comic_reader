import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'media_pool_config.dart';

/// Persists the single media-pool WebDAV connection: URL/username in Hive,
/// password in secure storage (same split as [ServerStore]/[KapowarrConfigStore]).
class MediaPoolConfigStore {
  static const _boxName = 'media_pool_config';
  static const _urlKey = 'baseUrl';
  static const _userKey = 'username';
  static const _passwordStorageKey = 'media_pool_password';

  final FlutterSecureStorage _secure;
  late final Box<String> _box;

  /// Called after every save/delete - set by ConnectionsSync.
  void Function()? onChanged;

  MediaPoolConfigStore({FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ?? const FlutterSecureStorage();

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  bool get hasConfig => _box.containsKey(_urlKey);

  Future<MediaPoolConfig?> getWithPassword() async {
    final url = _box.get(_urlKey);
    final username = _box.get(_userKey);
    if (url == null || username == null) return null;
    final password = await _secure.read(key: _passwordStorageKey) ?? '';
    return MediaPoolConfig(baseUrl: url, username: username, password: password);
  }

  Future<void> save(MediaPoolConfig config) async {
    await _box.put(_urlKey, config.baseUrl);
    await _box.put(_userKey, config.username);
    await _secure.write(key: _passwordStorageKey, value: config.password);
    onChanged?.call();
  }

  Future<void> clear() async {
    await _box.delete(_urlKey);
    await _box.delete(_userKey);
    await _secure.delete(key: _passwordStorageKey);
    onChanged?.call();
  }
}
