import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'sync_client.dart';

/// Durable queue of pushes to shaddai-sync that failed to send (offline,
/// server down, etc.) - directly adapted from [ProgressSync]'s proven
/// shape (Hive box keyed by id, try/catch-and-requeue) rather than written
/// fresh. Generic over "resource" (history, collections, ...) so every
/// synced store can share one queue implementation.
class SyncQueue {
  static const _boxName = 'sync_queue';

  late final Box<String> _box;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  String _key(String resource, String recordId) => '$resource::$recordId';

  /// Queues [record] for [resource] and immediately tries to flush that
  /// resource's whole queue - if the client has no valid session yet (not
  /// logged in), this just leaves it queued for the next flush attempt.
  Future<void> enqueue(SyncClient? client, String resource, SyncRecord record) async {
    await _box.put(_key(resource, record.recordId), jsonEncode(record.toJson()));
    if (client != null) {
      await flush(client, resource);
    }
  }

  /// Retries every queued push for [resource]. Entries that still fail
  /// stay queued for the next attempt.
  Future<void> flush(SyncClient client, String resource) async {
    final prefix = '$resource::';
    final pending = _box.keys
        .cast<String>()
        .where((k) => k.startsWith(prefix))
        .toList();
    if (pending.isEmpty) return;

    final records = <SyncRecord>[];
    for (final key in pending) {
      final raw = _box.get(key);
      if (raw == null) continue;
      records.add(SyncRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    }

    try {
      await client.push(resource, records);
      for (final key in pending) {
        await _box.delete(key);
      }
    } catch (_) {
      // Leave it queued; will retry on the next flush.
    }
  }
}
