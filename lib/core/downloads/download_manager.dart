import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../backend/models.dart';
import '../backend/reader_backend.dart';
import 'download_models.dart';
import 'download_store.dart';

/// Drives the download queue: up to [concurrency] books download at once,
/// each fetching pages sequentially through the same [ReaderBackend] the
/// reader uses. Pause/resume/cancel just flip queue state; the pump loop
/// picks the next queued task whenever a slot frees up.
class DownloadManager {
  static const concurrency = 2;

  final DownloadStore store;
  int _activeCount = 0;
  final StreamController<void> _changes = StreamController.broadcast();

  DownloadManager({required this.store});

  /// Fires on every queue/progress change - UI providers watch this.
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> enqueueBook(
    ReaderBackend backend, {
    required String bookId,
    required String seriesId,
    required String seriesTitle,
    required String title,
    required int totalPages,
  }) async {
    final existing = store.getTask(bookId);
    if (existing != null && existing.state != DownloadState.failed) return;

    await store.saveTask(DownloadTask(
      bookId: bookId,
      seriesId: seriesId,
      seriesTitle: seriesTitle,
      title: title,
      totalPages: totalPages,
      downloadedPages: existing?.downloadedPages ?? 0,
      state: DownloadState.queued,
    ));
    _notify();
    unawaited(_pump(backend));
  }

  Future<void> enqueueBooks(
    ReaderBackend backend,
    List<Book> books,
    String seriesId,
    String seriesTitle,
  ) async {
    for (final b in books) {
      await enqueueBook(
        backend,
        bookId: b.id,
        seriesId: seriesId,
        seriesTitle: seriesTitle,
        title: b.title,
        totalPages: b.pageCount,
      );
    }
  }

  Future<void> pause(String bookId) async {
    final task = store.getTask(bookId);
    if (task == null) return;
    if (task.state == DownloadState.queued || task.state == DownloadState.running) {
      await store.saveTask(task.copyWith(state: DownloadState.paused));
      _notify();
    }
  }

  Future<void> resume(String bookId, ReaderBackend backend) async {
    final task = store.getTask(bookId);
    if (task == null || task.state != DownloadState.paused) return;
    await store.saveTask(task.copyWith(state: DownloadState.queued));
    _notify();
    unawaited(_pump(backend));
  }

  Future<void> retry(String bookId, ReaderBackend backend) => resume(bookId, backend);

  Future<void> cancel(String bookId) async {
    await store.deleteTask(bookId);
    await store.deletePagesForBook(bookId);
    _notify();
  }

  Future<bool> _wifiOnlyBlocked() async {
    if (kIsWeb) return false;
    if (!store.wifiOnly) return false;
    final results = await Connectivity().checkConnectivity();
    return !results.contains(ConnectivityResult.wifi) &&
        !results.contains(ConnectivityResult.ethernet);
  }

  Future<void> _pump(ReaderBackend backend) async {
    while (_activeCount < concurrency) {
      final next = store.listTasks().where((t) => t.state == DownloadState.queued);
      if (next.isEmpty) return;
      _activeCount++;
      unawaited(_runTask(backend, next.first.bookId).whenComplete(() {
        _activeCount--;
        _pump(backend);
      }));
    }
  }

  Future<void> _runTask(ReaderBackend backend, String bookId) async {
    final initial = store.getTask(bookId);
    if (initial == null) return;

    DownloadTask latest = initial.copyWith(state: DownloadState.running);
    await store.saveTask(latest);
    _notify();

    try {
      for (var i = latest.downloadedPages; i < latest.totalPages; i++) {
        final current = store.getTask(bookId);
        if (current == null) return;
        if (current.state == DownloadState.paused) return;

        if (await _wifiOnlyBlocked()) {
          await store.saveTask(current.copyWith(state: DownloadState.paused));
          _notify();
          return;
        }

        if (!store.hasPage(bookId, i)) {
          final bytes = await backend.fetchPage(bookId, i);
          await store.putPage(bookId, i, bytes);
        }
        latest = current.copyWith(downloadedPages: i + 1);
        await store.saveTask(latest);
        _notify();
      }
      await store.saveTask(latest.copyWith(state: DownloadState.done));
    } catch (e) {
      final current = store.getTask(bookId);
      if (current != null) {
        await store.saveTask(current.copyWith(state: DownloadState.failed, error: '$e'));
      }
    }
    _notify();
  }

  void dispose() {
    _changes.close();
  }
}
