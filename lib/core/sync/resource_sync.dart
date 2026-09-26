import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'sync_client.dart';
import 'sync_queue.dart';

/// Last-write-wins sync for one shaddai-sync resource backed by one Hive
/// box (collections, appearance, reader settings). Every box entry is
/// keyed by its sync record id and its JSON carries an `_at` timestamp;
/// the newest `_at` wins on either side, deletions travel as tombstones.
/// Local-only until [attach] is called with a signed-in session.
class ResourceSync {
  static const lastSyncKey = '_last_sync';
  static final _epoch = DateTime.utc(1970);

  final String resource;
  SyncClient? _client;
  SyncQueue? _queue;

  ResourceSync(this.resource);

  void attach(SyncClient client, SyncQueue queue) {
    _client = client;
    _queue = queue;
  }

  void detach() {
    _client = null;
    _queue = null;
  }

  static DateTime _at(String? raw) {
    if (raw == null) return _epoch;
    final at = (jsonDecode(raw) as Map<String, dynamic>)['_at'] as String?;
    return at == null ? _epoch : DateTime.parse(at);
  }

  /// Stamps [json], stores it under [id] and queues a push.
  Future<void> put(Box<String> box, String id, Map<String, dynamic> json) async {
    final at = DateTime.now().toUtc();
    final data = {...json, '_at': at.toIso8601String()};
    await box.put(id, jsonEncode(data));
    await _push(id, data, at, false);
  }

  Future<void> remove(Box<String> box, String id) async {
    final at = DateTime.now().toUtc();
    await box.delete(id);
    await _push(id, {}, at, true);
  }

  Future<void> _push(
      String id, Map<String, dynamic> data, DateTime at, bool deleted) async {
    final queue = _queue;
    if (_client == null || queue == null) return;
    await queue.enqueue(
      _client,
      resource,
      SyncRecord(
        recordId: id,
        data: data,
        updatedAt: at.toIso8601String(),
        deleted: deleted,
      ),
    );
  }

  /// Pulls remote changes into [box] (newer `_at` wins). On a first full
  /// pull, also uploads local entries the server has never seen. Returns
  /// true when the local box changed, so the caller can refresh its UI.
  Future<bool> reconcile(Box<String> box) async {
    final client = _client;
    if (client == null) return false;

    final since = box.get(lastSyncKey) ?? '';
    final remote = await client.pull(resource, since: since);

    var changed = false;
    var latest = since;
    for (final r in remote) {
      if (r.updatedAt.compareTo(latest) > 0) latest = r.updatedAt;
      final local = box.get(r.recordId);
      if (local != null && !DateTime.parse(r.updatedAt).isAfter(_at(local))) {
        continue;
      }
      if (r.deleted) {
        await box.delete(r.recordId);
      } else {
        await box.put(r.recordId, jsonEncode(r.data));
      }
      changed = true;
    }

    if (since.isEmpty) {
      final known = remote.map((r) => r.recordId).toSet();
      for (final key in box.keys.cast<String>()) {
        // `_`-prefixed keys are local bookkeeping (last-sync marker, per-
        // device flags), never records.
        if (key.startsWith('_') || known.contains(key)) continue;
        final raw = box.get(key)!;
        await _push(key, jsonDecode(raw) as Map<String, dynamic>, _at(raw), false);
      }
    }
    if (latest != since) await box.put(lastSyncKey, latest);
    return changed;
  }
}
