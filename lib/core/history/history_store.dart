import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../sync/sync_client.dart';
import '../sync/sync_queue.dart';
import 'history_entry.dart';

/// Reading history (6e) - one row per book, keyed by bookId so re-reading
/// the same chapter updates its timestamp/progress instead of piling up
/// duplicate rows. Cached locally in Hive (instant, works offline) and,
/// once [attachSync] has been called with a signed-in session, pushed to
/// shaddai-sync and reconciled across devices - see [reconcile].
class HistoryStore {
  static const _boxName = 'reading_history';
  static const _lastSyncKey = '_last_sync';

  late final Box<String> _box;
  SyncClient? _syncClient;
  SyncQueue? _syncQueue;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  /// Wires this store to a signed-in sync session - called once after
  /// login/app-resume. Before this is called, the store behaves exactly
  /// as it did before sync existed: local-only.
  void attachSync(SyncClient client, SyncQueue queue) {
    _syncClient = client;
    _syncQueue = queue;
  }

  void detachSync() {
    _syncClient = null;
    _syncQueue = null;
  }

  Future<void> record(HistoryEntry entry) async {
    await _box.put(entry.bookId, jsonEncode(entry.toJson()));
    final client = _syncClient;
    final queue = _syncQueue;
    if (client != null && queue != null) {
      await queue.enqueue(
        client,
        'history',
        SyncRecord(
          recordId: entry.bookId,
          data: entry.toJson(),
          updatedAt: entry.timestamp.toIso8601String(),
        ),
      );
    }
  }

  /// Newest first.
  List<HistoryEntry> list() {
    final entries = _box.keys
        .where((k) => k != _lastSyncKey)
        .map((k) => HistoryEntry.fromJson(jsonDecode(_box.get(k)!) as Map<String, dynamic>))
        .toList();
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  Future<void> clear() => _box.clear();

  /// Pulls every history change from the server since the last reconcile
  /// and merges it into the local box - server wins per book only if its
  /// timestamp is newer (natural last-write-wins, matching the model's
  /// existing per-book semantics). Safe to call repeatedly (e.g. on every
  /// app resume); a fresh install with no prior sync does a full pull.
  Future<void> reconcile() async {
    final client = _syncClient;
    if (client == null) return;

    final since = _box.get(_lastSyncKey) ?? '';
    final remote = await client.pull('history', since: since);
    if (remote.isEmpty) return;

    var latest = since;
    for (final record in remote) {
      final entry = HistoryEntry.fromJson(record.data);
      final localRaw = _box.get(entry.bookId);
      if (localRaw != null) {
        final local = HistoryEntry.fromJson(jsonDecode(localRaw) as Map<String, dynamic>);
        if (local.timestamp.isAfter(entry.timestamp)) continue;
      }
      await _box.put(entry.bookId, jsonEncode(entry.toJson()));
      if (record.updatedAt.compareTo(latest) > 0) latest = record.updatedAt;
    }
    if (latest != since) {
      await _box.put(_lastSyncKey, latest);
    }
  }
}
