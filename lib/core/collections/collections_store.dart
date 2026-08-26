import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'collection.dart';

/// CRUD for local Collections (6d) - one Hive box, each entry a JSON-encoded
/// [LocalCollection] keyed by its id.
class CollectionsStore {
  static const _boxName = 'collections';
  static const _uuid = Uuid();

  late final Box<String> _box;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  List<LocalCollection> list() {
    final items = _box.values
        .map((raw) => LocalCollection.fromJson(jsonDecode(raw) as Map<String, dynamic>))
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
    await _box.put(collection.id, jsonEncode(collection.toJson()));
    return collection;
  }

  Future<void> delete(String id) => _box.delete(id);

  Future<void> addSeries(String collectionId, String seriesId) async {
    final raw = _box.get(collectionId);
    if (raw == null) return;
    final c = LocalCollection.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    if (c.seriesIds.contains(seriesId)) return;
    final updated = c.copyWith(seriesIds: [...c.seriesIds, seriesId]);
    await _box.put(collectionId, jsonEncode(updated.toJson()));
  }

  Future<void> removeSeries(String collectionId, String seriesId) async {
    final raw = _box.get(collectionId);
    if (raw == null) return;
    final c = LocalCollection.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    final updated = c.copyWith(
        seriesIds: c.seriesIds.where((id) => id != seriesId).toList());
    await _box.put(collectionId, jsonEncode(updated.toJson()));
  }
}
