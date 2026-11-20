import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';

import 'download_models.dart';

/// Persists the download queue (task metadata) and the downloaded page
/// bytes themselves, both in Hive so they survive a reload/reinstall of
/// the PWA the way IndexedDB-backed storage does on web.
///
/// Deliberately separate from [PageCache]: that's an opportunistic,
/// LRU-evictable cache for whatever was recently read. This is a durable,
/// user-requested download that the reader should prefer over network
/// even after the app restarts.
class DownloadStore {
  static const _tasksBoxName = 'download_tasks';
  static const _pagesBoxName = 'download_pages';
  static const _sizesBoxName = 'download_page_sizes';
  static const _settingsBoxName = 'download_settings';
  static const _wifiOnlyKey = 'wifiOnly';

  late final Box<String> _tasksBox;

  /// Lazy: a plain Hive box reads every value into memory when it opens, and
  /// a few hundred downloaded chapters ran iPhones out of memory at launch.
  /// Only the keys stay in memory; each page is read from disk when asked.
  late final LazyBox<Uint8List> _pagesBox;

  /// Byte size of each page, by the same key, so storage totals don't have
  /// to read every page back from disk.
  late final Box<int> _sizesBox;
  late final Box<String> _settingsBox;

  Future<void> init() async {
    _tasksBox = await Hive.openBox<String>(_tasksBoxName);
    _pagesBox = await Hive.openLazyBox<Uint8List>(_pagesBoxName);
    _sizesBox = await Hive.openBox<int>(_sizesBoxName);
    _settingsBox = await Hive.openBox<String>(_settingsBoxName);
    unawaited(_backfillSizes());
  }

  /// Pages saved before sizes were tracked: measure them once, one at a time.
  Future<void> _backfillSizes() async {
    final missing =
        _pagesBox.keys.where((k) => !_sizesBox.containsKey(k)).toList();
    for (final key in missing) {
      if (!_pagesBox.isOpen) return;
      final bytes = await _pagesBox.get(key);
      if (bytes != null) await _sizesBox.put(key, bytes.lengthInBytes);
    }
  }

  /// In queue order (see [DownloadTask.order]), ties broken by book id so the
  /// result is stable.
  List<DownloadTask> listTasks() {
    final tasks = _tasksBox.values
        .map((raw) => DownloadTask.fromJson(jsonDecode(raw) as Map<String, dynamic>))
        .toList();
    tasks.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.bookId.compareTo(b.bookId);
    });
    return tasks;
  }

  DownloadTask? getTask(String bookId) {
    final raw = _tasksBox.get(bookId);
    if (raw == null) return null;
    return DownloadTask.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveTask(DownloadTask task) {
    return _tasksBox.put(task.bookId, jsonEncode(task.toJson()));
  }

  Future<void> deleteTask(String bookId) => _tasksBox.delete(bookId);

  String _pageKey(String bookId, int pageIndex) => '${bookId}_$pageIndex';

  Future<void> putPage(String bookId, int pageIndex, Uint8List bytes) async {
    final key = _pageKey(bookId, pageIndex);
    await _pagesBox.put(key, bytes);
    await _sizesBox.put(key, bytes.lengthInBytes);
  }

  Future<Uint8List?> getPage(String bookId, int pageIndex) =>
      _pagesBox.get(_pageKey(bookId, pageIndex));

  bool hasPage(String bookId, int pageIndex) =>
      _pagesBox.containsKey(_pageKey(bookId, pageIndex));

  Future<void> deletePagesForBook(String bookId) async {
    final prefix = '${bookId}_';
    final keys =
        _pagesBox.keys.where((k) => (k as String).startsWith(prefix)).toList();
    await _pagesBox.deleteAll(keys);
    await _sizesBox.deleteAll(keys);
  }

  /// Total bytes downloaded for every book belonging to [seriesId].
  int sizeForSeries(String seriesId) {
    final bookIds = {
      for (final t in listTasks().where((t) => t.seriesId == seriesId)) ...[
        t.bookId,
        ?t.sourceBookId,
      ],
    };
    var total = 0;
    for (final key in _sizesBox.keys) {
      final bookId = (key as String).split('_').first;
      if (bookIds.contains(bookId)) total += _sizesBox.get(key) ?? 0;
    }
    return total;
  }

  int get totalSize => _sizesBox.values.fold<int>(0, (a, b) => a + b);

  Future<void> clearSeries(String seriesId) async {
    for (final t in listTasks().where((t) => t.seriesId == seriesId)) {
      await deletePagesForBook(t.bookId);
      if (t.sourceBookId != null) await deletePagesForBook(t.sourceBookId!);
      await deleteTask(t.bookId);
    }
  }

  Future<void> clearAll() async {
    await _pagesBox.clear();
    await _sizesBox.clear();
    await _tasksBox.clear();
  }

  bool get wifiOnly => _settingsBox.get(_wifiOnlyKey) == 'true';

  Future<void> setWifiOnly(bool value) =>
      _settingsBox.put(_wifiOnlyKey, value.toString());
}
