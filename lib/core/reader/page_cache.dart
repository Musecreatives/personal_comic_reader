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

  late final Box<Uint8List> _box;
  final LinkedHashMap<String, Uint8List> _memory = LinkedHashMap();
  final Set<String> _inFlight = {};
  final DownloadStore? downloadStore;

  PageCache({this.downloadStore});

  Future<void> init() async {
    _box = await Hive.openBox<Uint8List>(_boxName);
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

    final downloaded = downloadStore?.getPage(bookId, pageIndex);
    if (downloaded != null) {
      _store(key, downloaded);
      return downloaded;
    }

    final onDisk = _box.get(key);
    if (onDisk != null) {
      _store(key, onDisk);
      return onDisk;
    }

    final bytes = await backend.fetchPage(bookId, pageIndex);
    _store(key, bytes);
    unawaited(_box.put(key, bytes));
    return bytes;
  }

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
          unawaited(_box.put(key, bytes));
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
