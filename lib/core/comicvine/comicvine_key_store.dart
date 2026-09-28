import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The optional ComicVine API key, in secure storage like the Kapowarr key.
/// There's nothing else to configure (the API URL is fixed), so unlike
/// KapowarrConfigStore there's no Hive box, config class or init.
class ComicVineKeyStore {
  static const _storageKey = 'comicvine_api_key';

  final FlutterSecureStorage _secure;

  ComicVineKeyStore({FlutterSecureStorage? secureStorage})
    : _secure = secureStorage ?? const FlutterSecureStorage();

  /// Null when no key is set.
  Future<String?> get() async {
    final key = (await _secure.read(key: _storageKey))?.trim();
    return key == null || key.isEmpty ? null : key;
  }

  Future<void> save(String apiKey) =>
      _secure.write(key: _storageKey, value: apiKey.trim());

  Future<void> clear() => _secure.delete(key: _storageKey);
}
