import 'package:hive_flutter/hive_flutter.dart';

/// Persists the one folder auto-imported from, plus which entries under it
/// have already been imported (by full path) so a restart doesn't re-import
/// everything sitting there.
class WatchFolderStore {
  static const _configBoxName = 'watch_folder_config';
  static const _pathKey = 'path';
  static const _seenBoxName = 'watch_folder_seen';

  late final Box<String> _configBox;
  late final Box<bool> _seenBox;

  Future<void> init() async {
    _configBox = await Hive.openBox<String>(_configBoxName);
    _seenBox = await Hive.openBox<bool>(_seenBoxName);
  }

  String? get path => _configBox.get(_pathKey);

  Future<void> setPath(String? path) async {
    if (path == null) {
      await _configBox.delete(_pathKey);
    } else {
      await _configBox.put(_pathKey, path);
    }
  }

  bool hasSeen(String entryPath) => _seenBox.containsKey(entryPath);

  Future<void> markSeen(String entryPath) => _seenBox.put(entryPath, true);
}
