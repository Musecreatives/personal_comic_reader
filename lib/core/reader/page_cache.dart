import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';

import '../backend/reader_backend.dart';
import '../downloads/download_store.dart';

/// Loads page bytes for a book, keeping a bounded in-memory LRU cache and a
/// Hive-backed disk cache so re-opening a book (or going offline) doesn't
/// always hit the network.
///
/// One instance is scoped to a single reader session (one book at a time);
/// [prefetch] fires network requests without awaiting them so scrolling/
/// paging stays responsive.
///
/// When [downloadStore] is provided, a deliberately-downloaded page always
/// wins over the network - offline-first, per the download feature's whole
/// point - checked before this cache's own (evictable, opportunistic) disk
/// tier.
class PageCache {
  static const _boxName = 'page_cache';
  static const _memoryCapacity = 12;

  /// Pages kept on disk (~a few hundred MB). Nothing trimmed it before, and
  /// it grew with every page read online.
  static const diskCapacity = 800;

  /// Lazy, like the download store's pages: a plain box reads every page
  /// into memory when it opens, which ran iPhones out of memory at launch.
  late final LazyBox<Uint8List> _box;
  final LinkedHashMap<String, Uint8List> _memory = LinkedHashMap();
  final Set<String> _inFlight = {};
  final DownloadStore? downloadStore;

  /// How long one page request may take before it counts as failed. A
  /// source that stops answering used to leave the reader spinning forever.
  final Duration pageTimeout;

  final _failures =
      StreamController<({String bookId, int pageIndex})>.broadcast();

  PageCache({this.downloadStore, this.pageTimeout = const Duration(seconds: 20)});

  /// Pages the reader asked for that still failed after a retry. The reader
  /// listens to switch a chapter to a backup source.
  Stream<({String bookId, int pageIndex})> get failures => _failures.stream;

  Future<void> init() async {
    _box = await Hive.openLazyBox<Uint8List>(_boxName);
    await _trim();
  }

  /// ponytail: drops the first keys in Hive's (sorted) key order, not the
  /// least recently read; a cache miss just refetches. Track read times if
  /// that ever evicts something in use.
  Future<void> _trim() async {
    final over = _box.length - diskCapacity;
    if (over > 0) await _box.deleteAll(_box.keys.take(over).toList());
  }

  /// Fire-and-forget: a page that fails to cache (box closed, disk full) is
  /// just fetched again next time.
  Future<void> _save(String key, Uint8List bytes) async {
    try {
      await _box.put(key, bytes);
      await _trim();
    } catch (_) {}
  }

  String _key(String bookId, int pageIndex) => '${bookId}_$pageIndex';

  Future<Uint8List> getPage(
    ReaderBackend backend,
    String bookId,
    int pageIndex,
  ) async {
    final key = _key(bookId, pageIndex);

    final cached = _memory[key];
    if (cached != null) {
      _touch(key, cached);
      return cached;
    }

    final downloaded = await downloadStore?.getPage(bookId, pageIndex);
    if (downloaded != null) {
      _store(key, downloaded);
      return downloaded;
    }

    final onDisk = await _box.get(key);
    if (onDisk != null) {
      _store(key, onDisk);
      return onDisk;
    }

    final Uint8List bytes;
    try {
      bytes = await _fetchWithRetry(backend, bookId, pageIndex);
    } catch (_) {
      _failures.add((bookId: bookId, pageIndex: pageIndex));
      rethrow;
    }
    _store(key, bytes);
    if (_persist(backend)) unawaited(_save(key, bytes));
    return bytes;
  }

  /// One request with [pageTimeout], then one more; the second error is
  /// the one thrown.
  Future<Uint8List> _fetchWithRetry(
      ReaderBackend backend, String bookId, int pageIndex) async {
    try {
      return await backend.fetchPage(bookId, pageIndex).timeout(pageTimeout);
    } catch (_) {
      return backend.fetchPage(bookId, pageIndex).timeout(pageTimeout);
    }
  }

  /// Local books are already on disk - copying their pages into this cache
  /// would just duplicate them (and a single omnibus can be gigabytes).
  bool _persist(ReaderBackend backend) =>
      backend.config.type != ServerType.local;

  /// Fire-and-forget prefetch of [count] pages starting at [fromIndex] and
  /// moving in [step] (+1 forward, -1 backward). Errors are swallowed - a
  /// prefetch miss just means a later on-demand fetch pays the cost.
  void prefetch(
    ReaderBackend backend,
    String bookId,
    int fromIndex,
    int totalPages, {
    int count = 3,
    int step = 1,
  }) {
    var index = fromIndex;
    var fetched = 0;
    while (fetched < count) {
      if (index < 0 || index >= totalPages) break;
      final key = _key(bookId, index);
      if (!_memory.containsKey(key) &&
          !_box.containsKey(key) &&
          (downloadStore?.hasPage(bookId, index) ?? false) == false &&
          !_inFlight.contains(key)) {
        _inFlight.add(key);
        backend.fetchPage(bookId, index).then((bytes) {
          _store(key, bytes);
          if (_persist(backend)) unawaited(_save(key, bytes));
        }).catchError((_) {}).whenComplete(() => _inFlight.remove(key));
      }
      index += step;
      fetched++;
    }
  }

  void _store(String key, Uint8List bytes) {
    _memory[key] = bytes;
    _touch(key, bytes);
  }

  void _touch(String key, Uint8List bytes) {
    _memory.remove(key);
    _memory[key] = bytes;
    while (_memory.length > _memoryCapacity) {
      _memory.remove(_memory.keys.first);
    }
  }

  /// Clears cached pages for [bookId] from memory and disk.
  Future<void> clearBook(String bookId) async {
    final prefix = '${bookId}_';
    _memory.removeWhere((k, _) => k.startsWith(prefix));
    final diskKeys = _box.keys.where((k) => (k as String).startsWith(prefix));
    await _box.deleteAll(diskKeys);
  }
}
