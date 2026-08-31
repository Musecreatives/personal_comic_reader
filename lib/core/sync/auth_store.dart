import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the signed-in shaddai-sync session (bearer token + username)
/// in secure storage, mirroring [ServerStore]'s pattern for the same
/// package - web-safe (IndexedDB + WebCrypto), no shared_preferences
/// fallback needed.
class AuthStore {
  static const _tokenKey = 'sync_auth_token';
  static const _usernameKey = 'sync_auth_username';

  final FlutterSecureStorage _secure;

  AuthStore({FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ?? const FlutterSecureStorage();

  Future<String?> getToken() => _secure.read(key: _tokenKey);

  Future<String?> getUsername() => _secure.read(key: _usernameKey);

  Future<void> saveSession({required String token, required String username}) async {
    await _secure.write(key: _tokenKey, value: token);
    await _secure.write(key: _usernameKey, value: username);
  }

  Future<void> clear() async {
    await _secure.delete(key: _tokenKey);
    await _secure.delete(key: _usernameKey);
  }
}
