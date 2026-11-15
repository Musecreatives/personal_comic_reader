import 'package:hive_flutter/hive_flutter.dart';

import '../sync/resource_sync.dart';

/// Backup sources this account has switched off for a title: the owner's
/// backup list stays as it is for everyone else, and the reader and
/// downloads just never fall back to these for this account. Synced per
/// account. Keyed `seriesId|backupId` (Suwayomi manga ids).
class SkippedBackupsStore {
  static const boxName = 'skipped_backups';

  late final Box<String> _box;
  final sync = ResourceSync('skipped_backups');

  Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
  }

  Future<bool> reconcile() => sync.reconcile(_box);

  static String _key(String seriesId, int backupId) => '$seriesId|$backupId';

  bool isSkipped(String seriesId, int backupId) =>
      _box.containsKey(_key(seriesId, backupId));

  Future<void> setSkipped(String seriesId, int backupId, bool skipped) =>
      skipped
          ? sync.put(_box, _key(seriesId, backupId), const {})
          : sync.remove(_box, _key(seriesId, backupId));
}
