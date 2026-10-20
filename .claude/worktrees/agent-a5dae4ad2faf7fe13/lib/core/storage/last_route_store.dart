import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the last route visited so the PWA can reopen there instead of
/// always landing on /home - most useful offline, where re-navigating from
/// scratch may not even be possible if a screen needs network to load.
class LastRouteStore {
  static const _key = 'last_route';
  static const _serverKey = 'last_route_server';

  /// The active server when a route is saved. Ids in a route (a series, a
  /// library) only mean something to the server they came from.
  final String? Function() activeServerId;

  LastRouteStore({required this.activeServerId});

  /// Null unless the route was saved under the server that's active now -
  /// reopening a local series against Suwayomi fed its UUID to int.parse and
  /// left the app on an error screen at every launch.
  Future<String?> getLastRoute() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_serverKey) != activeServerId()) return null;
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
    final server = activeServerId();
    if (server == null) {
      await prefs.remove(_serverKey);
    } else {
      await prefs.setString(_serverKey, server);
    }
  }
}
