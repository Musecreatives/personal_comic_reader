import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'history_entry.dart';

/// Local-only reading history (6e) - one row per book, keyed by bookId so
/// re-reading the same chapter updates its timestamp/progress instead of
/// piling up duplicate rows. Never synced to a server.
class HistoryStore {
  static const _boxName = 'reading_history';

  late final Box<String> _box;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  Future<void> record(HistoryEntry entry) {
    return _box.put(entry.bookId, jsonEncode(entry.toJson()));
  }

  /// Newest first.
  List<HistoryEntry> list() {
    final entries = _box.values
        .map((raw) => HistoryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>))
        .toList();
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  Future<void> clear() => _box.clear();
}
