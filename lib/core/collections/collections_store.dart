import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../sync/resource_sync.dart';
import 'collection.dart';

/// CRUD for local Collections (6d) - one Hive box, each entry a JSON-encoded
/// [LocalCollection] keyed by its id.
class CollectionsStore {
  static const _boxName = 'collections';
  static const _uuid = Uuid();

  late final Box<String> _box;
  final sync = ResourceSync('collections');

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  Future<bool> reconcile() => sync.reconcile(_box);

  Future<void> _save(LocalCollection c) => sync.put(_box, c.id, c.toJson());

  List<LocalCollection> list() {
    final items = _box.keys
        .where((k) => k != ResourceSync.lastSyncKey)
        .map((k) => LocalCollection.fromJson(
            jsonDecode(_box.get(k)!) as Map<String, dynamic>))
        .toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<LocalCollection> create(String name) async {
    final collection = LocalCollection(
      id: _uuid.v4(),
      name: name,
      seriesIds: const [],
      createdAt: DateTime.now(),
    );
    await _save(collection);
    return collection;
  }

  Future<void> delete(String id) => sync.remove(_box, id);

  LocalCollection? get(String id) {
    final raw = _box.get(id);
    if (raw == null) return null;
    return LocalCollection.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> rename(String id, String name) async {
    final c = get(id);
    if (c != null) await _save(c.copyWith(name: name));
  }

  Future<void> addSeries(String collectionId, String seriesId) async {
    final raw = _box.get(collectionId);
    if (raw == null) return;
    final c = LocalCollection.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    if (c.seriesIds.contains(seriesId)) return;
    await _save(c.copyWith(seriesIds: [...c.seriesIds, seriesId]));
  }

  Future<void> removeSeries(String collectionId, String seriesId) async {
    final raw = _box.get(collectionId);
    if (raw == null) return;
    final c = LocalCollection.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    await _save(c.copyWith(
        seriesIds: c.seriesIds.where((id) => id != seriesId).toList()));
  }
}
