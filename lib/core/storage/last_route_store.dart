import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the last route visited so the PWA can reopen there instead of
/// always landing on /home - most useful offline, where re-navigating from
/// scratch may not even be possible if a screen needs network to load.
class LastRouteStore {
  static const _key = 'last_route';

  Future<String?> getLastRoute() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  Future<void> setLastRoute(String path) async {
    // Never resume into the reader or a modal-ish add/edit form - those
    // need specific IDs/state that a cold start can't safely replay.
    if (path.startsWith('/read/') ||
        path.contains('/new') ||
        path.contains('/edit')) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, path);
  }
}
