import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'kapowarr_config.dart';

/// Persists the single Kapowarr connection: base URL in Hive, API key in
/// secure storage (same split as [ServerStore] uses for passwords).
class KapowarrConfigStore {
  static const _boxName = 'kapowarr_config';
  static const _urlKey = 'baseUrl';
  static const _apiKeyStorageKey = 'kapowarr_api_key';

  final FlutterSecureStorage _secure;
  late final Box<String> _box;

  KapowarrConfigStore({FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ?? const FlutterSecureStorage();

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  bool get hasConfig => _box.containsKey(_urlKey);

  Future<KapowarrConfig?> getWithApiKey() async {
    final url = _box.get(_urlKey);
    if (url == null) return null;
    final apiKey = await _secure.read(key: _apiKeyStorageKey) ?? '';
    return KapowarrConfig(baseUrl: url, apiKey: apiKey);
  }

  Future<void> save(KapowarrConfig config) async {
    await _box.put(_urlKey, config.baseUrl);
    await _secure.write(key: _apiKeyStorageKey, value: config.apiKey);
  }

  Future<void> clear() async {
    await _box.delete(_urlKey);
    await _secure.delete(key: _apiKeyStorageKey);
  }
}
