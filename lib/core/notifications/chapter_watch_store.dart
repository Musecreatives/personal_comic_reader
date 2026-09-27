import 'package:hive_flutter/hive_flutter.dart';

/// Tracks the last-known chapter count per series (keyed `<serverId>|<seriesId>`)
/// so [ChapterNotificationScheduler] can tell "gained a chapter since last
/// check" from "first time seeing this series".
class ChapterWatchStore {
  static const _boxName = 'chapter_watch';
  late final Box<int> _box;

  Future<void> init() async {
    _box = await Hive.openBox<int>(_boxName);
  }

  int? lastKnownCount(String key) => _box.get(key);

  Future<void> setCount(String key, int count) => _box.put(key, count);
}
