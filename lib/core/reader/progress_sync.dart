import 'dart:async';
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../backend/reader_backend.dart';

/// Debounces [ReaderBackend.updateProgress] calls and keeps a durable queue
/// of updates that failed to send, flushing them on the next opportunity.
class ProgressSync {
  static const _boxName = 'progress_queue';
  static const _debounce = Duration(seconds: 1);

  late final Box<String> _box;
  Timer? _debounceTimer;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  /// Schedules a progress update for [bookId], debounced by 1s. Any
  /// previously scheduled-but-not-yet-sent update for a *different* book is
  /// unaffected; only one pending timer per call site is expected since the
  /// reader only tracks one open book at a time.
  void scheduleUpdate(
    ReaderBackend backend,
    String bookId, {
    required int page,
    bool completed = false,
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      _send(backend, bookId, page: page, completed: completed);
    });
  }

  /// Sends immediately, bypassing the debounce (e.g. on book completion or
  /// when leaving the reader).
  Future<void> sendNow(
    ReaderBackend backend,
    String bookId, {
    required int page,
    bool completed = false,
  }) {
    _debounceTimer?.cancel();
    return _send(backend, bookId, page: page, completed: completed);
  }

  Future<void> _send(
    ReaderBackend backend,
    String bookId, {
    required int page,
    bool completed = false,
  }) async {
    try {
      await backend.updateProgress(bookId, page: page, completed: completed);
      await _box.delete(bookId);
      await flushQueue(backend);
    } catch (_) {
      await _box.put(
        bookId,
        jsonEncode({'page': page, 'completed': completed}),
      );
    }
  }

  /// Retries every queued update against [backend]. Entries that still fail
  /// stay queued for the next attempt.
  Future<void> flushQueue(ReaderBackend backend) async {
    for (final bookId in _box.keys.toList()) {
      final raw = _box.get(bookId);
      if (raw == null) continue;
      final entry = jsonDecode(raw) as Map<String, dynamic>;
      try {
        await backend.updateProgress(
          bookId as String,
          page: entry['page'] as int,
          completed: entry['completed'] as bool? ?? false,
        );
        await _box.delete(bookId);
      } catch (_) {
        // Leave it queued; will retry on the next flush.
      }
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
  }
}
