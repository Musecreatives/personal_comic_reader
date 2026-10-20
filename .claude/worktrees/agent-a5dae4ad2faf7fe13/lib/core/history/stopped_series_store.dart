import 'package:hive_flutter/hive_flutter.dart';

/// Series the user has chosen to stop reading. They vanish from Home (hero,
/// "Continue reading", the now-reading pill) but nothing changes on the
/// server, and history is kept. Reading one again brings it back.
///
/// Keyed by `serverId|seriesId`, holding when it was stopped; a series
/// counts as stopped only while its latest read is not newer than that.
class StoppedSeriesStore {
  static const _boxName = 'stopped_series';

  late final Box<String> _box;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  Future<void> stop(String key) =>
      _box.put(key, DateTime.now().toUtc().toIso8601String());

  Future<void> resume(String key) => _box.delete(key);

  /// True while [key] is stopped. [lastReadAt] is when it was last read
  /// (null when there is no history for it): a read after the stop revives it.
  bool isStopped(String key, {DateTime? lastReadAt}) {
    final raw = _box.get(key);
    if (raw == null) return false;
    final stoppedAt = DateTime.parse(raw);
    return lastReadAt == null || !lastReadAt.toUtc().isAfter(stoppedAt);
  }
}
