import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../backend/models.dart';
import '../backend/reader_backend.dart';
import 'download_models.dart';
import 'download_store.dart';

typedef ChapterFallback = Future<({String bookId, int pageCount})?> Function(
    ReaderBackend backend, String bookId);

/// Drives the download queue: up to [concurrency] books download at once,
/// each fetching pages sequentially through the same [ReaderBackend] the
/// reader uses. Pause/resume/cancel just flip queue state; the pump loop
/// picks the next queued task whenever a slot frees up.
class DownloadManager {
  static const concurrency = 2;

  final DownloadStore store;
  int _activeCount = 0;

  /// The backend each queued book must be fetched from. In memory only: after
  /// an app restart a task stays put until the user resumes it (which
  /// re-registers its backend), rather than guessing a server.
  final Map<String, ReaderBackend> _backends = {};
  final Set<String> _running = {};
  final StreamController<void> _changes = StreamController.broadcast();

  /// Finds a chapter's copy on a backup source when its own source can't
  /// serve it: that copy's book id and page count, or null. Supplied by the
  /// app for Suwayomi; without it a failed page fails the download.
  final ChapterFallback? findFallback;

  DownloadManager({required this.store, this.findFallback});

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

    final tasks = store.listTasks();
    final nextOrder = tasks.isEmpty ? 0 : tasks.map((t) => t.order).reduce((a, b) => a > b ? a : b) + 1;
    _backends[bookId] = backend;
    await store.saveTask(DownloadTask(
      bookId: bookId,
      seriesId: seriesId,
      seriesTitle: seriesTitle,
      title: title,
      totalPages: totalPages,
      downloadedPages: existing?.downloadedPages ?? 0,
      state: DownloadState.queued,
      serverId: backend.config.id,
      order: nextOrder,
    ));
    _notify();
    unawaited(_pump());
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
    if (task == null ||
        (task.state != DownloadState.paused && task.state != DownloadState.failed)) {
      return;
    }
    _backends[bookId] = backend;
    await store.saveTask(task.copyWith(state: DownloadState.queued));
    _notify();
    unawaited(_pump());
  }

  Future<void> retry(String bookId, ReaderBackend backend) => resume(bookId, backend);

  /// Removes a book from the queue and deletes whatever pages were saved.
  Future<void> cancel(String bookId) async {
    _backends.remove(bookId);
    final source = store.getTask(bookId)?.sourceBookId;
    await store.deleteTask(bookId);
    await store.deletePagesForBook(bookId);
    if (source != null) await store.deletePagesForBook(source);
    _notify();
  }

  /// Deletes every downloaded (or queued) chapter of a series from the device.
  Future<void> cancelSeries(String seriesId) async {
    for (final t in store.listTasks().where((t) => t.seriesId == seriesId)) {
      await cancel(t.bookId);
    }
  }

  /// Moves a queued book to the front of the line.
  Future<void> moveToTop(String bookId) async {
    final task = store.getTask(bookId);
    if (task == null) return;
    final tasks = store.listTasks();
    final lowest = tasks.isEmpty ? 0 : tasks.first.order; // listTasks is sorted
    await store.saveTask(task.copyWith(order: lowest - 1));
    _notify();
  }

  /// Applies a new queue order, given book ids from first to last.
  Future<void> reorder(List<String> bookIdsInOrder) async {
    for (var i = 0; i < bookIdsInOrder.length; i++) {
      final task = store.getTask(bookIdsInOrder[i]);
      if (task != null && task.order != i) {
        await store.saveTask(task.copyWith(order: i));
      }
    }
    _notify();
  }

  /// Drops failed tasks (and their partial pages) from the list.
  Future<void> clearFailed() async {
    for (final t in store.listTasks().where((t) => t.state == DownloadState.failed)) {
      await cancel(t.bookId);
    }
  }

  Future<bool> _wifiOnlyBlocked() async {
    if (kIsWeb) return false;
    if (!store.wifiOnly) return false;
    final results = await Connectivity().checkConnectivity();
    return !results.contains(ConnectivityResult.wifi) &&
        !results.contains(ConnectivityResult.ethernet);
  }

  /// After an app restart the in-memory backends are gone, so queued tasks
  /// (and any that were mid-download when the app closed) would sit waiting
  /// for a tap. Re-attach each to its server's backend and carry on. Tasks
  /// for a server that no longer exists, or predates server tracking, are
  /// left for the user to resume.
  Future<void> resumePending(Map<String, ReaderBackend> byServer) async {
    for (final t in store.listTasks()) {
      if (t.state != DownloadState.queued && t.state != DownloadState.running) {
        continue;
      }
      final backend = byServer[t.serverId];
      if (backend == null || _running.contains(t.bookId)) continue;
      _backends[t.bookId] = backend;
      if (t.state == DownloadState.running) {
        await store.saveTask(t.copyWith(state: DownloadState.queued));
      }
    }
    _notify();
    await _pump();
  }

  Future<void> _pump() async {
    while (_activeCount < concurrency) {
      // Queue order first; only tasks whose server we know how to reach.
      final next = store.listTasks().where((t) =>
          t.state == DownloadState.queued &&
          !_running.contains(t.bookId) &&
          _backends.containsKey(t.bookId));
      if (next.isEmpty) return;
      final bookId = next.first.bookId;
      final backend = _backends[bookId]!;
      _running.add(bookId);
      _activeCount++;
      unawaited(_runTask(backend, bookId).whenComplete(() {
        _running.remove(bookId);
        _activeCount--;
        _pump();
      }));
    }
  }

  Future<void> _runTask(ReaderBackend backend, String bookId) async {
    final initial = store.getTask(bookId);
    if (initial == null) return;
    await store.saveTask(initial.copyWith(state: DownloadState.running));
    _notify();

    try {
      try {
        await _download(backend, bookId);
      } catch (_) {
        // The main source failed: try the same chapter on a backup source
        // once (the reader does the same, see linked_sources.dart).
        final task = store.getTask(bookId);
        if (task == null || task.sourceBookId != null || findFallback == null) rethrow;
        ({String bookId, int pageCount})? copy;
        try {
          copy = await findFallback!(backend, bookId);
        } catch (_) {}
        if (copy == null) rethrow;
        // A different source's pages don't line up, so start this one over.
        await store.deletePagesForBook(bookId);
        await store.saveTask(task.copyWith(
            sourceBookId: copy.bookId, totalPages: copy.pageCount, downloadedPages: 0));
        _notify();
        await _download(backend, bookId);
      }
    } catch (e) {
      final current = store.getTask(bookId);
      if (current != null) {
        await store.saveTask(current.copyWith(state: DownloadState.failed, error: '$e'));
      }
    }
    _notify();
  }

  /// Saves the task's remaining pages, from its backup copy when it has one
  /// (stored under that copy's id, so an online read of the main chapter
  /// never picks up another source's pages), then marks it done.
  /// Returns early, leaving it unfinished, when it is paused, removed or
  /// held back by Wi-Fi only.
  Future<void> _download(ReaderBackend backend, String bookId) async {
    final saved = store.getTask(bookId);
    if (saved == null) return;
    var latest = saved;
    final fetchId = latest.sourceBookId ?? bookId;
    // Suwayomi (and OPDS) don't know a chapter's page count until it is
    // opened, so it was queued as 0. Ask for it now, or the loop below
    // would "finish" instantly having saved nothing.
    if (latest.totalPages == 0) {
      final book = await backend.getBook(fetchId);
      if (book.pageCount == 0) throw StateError('This chapter has no pages');
      latest = latest.copyWith(totalPages: book.pageCount);
      await store.saveTask(latest);
      _notify();
    }
    for (var i = latest.downloadedPages; i < latest.totalPages; i++) {
      final current = store.getTask(bookId);
      if (current == null) return;
      if (current.state == DownloadState.paused) return;

      if (await _wifiOnlyBlocked()) {
        await store.saveTask(current.copyWith(state: DownloadState.paused));
        _notify();
        return;
      }

      if (!store.hasPage(fetchId, i)) {
        final bytes = await backend.fetchPage(fetchId, i);
        await store.putPage(fetchId, i, bytes);
      }
      latest = current.copyWith(downloadedPages: i + 1);
      await store.saveTask(latest);
      _notify();
    }
    await store.saveTask(latest.copyWith(state: DownloadState.done));
  }

  /// Completes once no download is running, including the queue check each
  /// one runs as it finishes. Tests wait on it before closing storage, so a
  /// finishing download can't touch a closed box during the next test.
  Future<void> get idle async {
    while (_activeCount > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  void dispose() {
    _changes.close();
  }
}
