import 'package:hive_flutter/hive_flutter.dart';

import '../sync/resource_sync.dart';

/// Sources this account has hidden from search, browse and discovery.
/// Per account (synced), and nothing changes on the server: the owner and
/// other friends still see them. Keyed by Suwayomi source id.
class HiddenSourcesStore {
  static const _boxName = 'hidden_sources';

  late final Box<String> _box;
  final sync = ResourceSync('hidden_sources');

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  Future<bool> reconcile() => sync.reconcile(_box);

  bool isHidden(String sourceId) => _box.containsKey(sourceId);

  /// `_`-prefixed keys are sync bookkeeping, not sources.
  Set<String> get hiddenIds =>
      _box.keys.cast<String>().where((k) => !k.startsWith('_')).toSet();

  Future<void> setHidden(String sourceId, bool hidden) => hidden
      ? sync.put(_box, sourceId, const {})
      : sync.remove(_box, sourceId);

  /// [sources] without the hidden ones, in the same order.
  List<T> visible<T extends ({String id, String name, String lang})>(
          List<T> sources) =>
      sources.where((s) => !isHidden(s.id)).toList();
}
