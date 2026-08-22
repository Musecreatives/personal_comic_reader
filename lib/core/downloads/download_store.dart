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
  static const _settingsBoxName = 'download_settings';
  static const _wifiOnlyKey = 'wifiOnly';

  late final Box<String> _tasksBox;
  late final Box<Uint8List> _pagesBox;
  late final Box<String> _settingsBox;

  Future<void> init() async {
    _tasksBox = await Hive.openBox<String>(_tasksBoxName);
    _pagesBox = await Hive.openBox<Uint8List>(_pagesBoxName);
    _settingsBox = await Hive.openBox<String>(_settingsBoxName);
  }

  List<DownloadTask> listTasks() {
    return _tasksBox.values
        .map((raw) => DownloadTask.fromJson(jsonDecode(raw) as Map<String, dynamic>))
        .toList();
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

  Future<void> putPage(String bookId, int pageIndex, Uint8List bytes) {
    return _pagesBox.put(_pageKey(bookId, pageIndex), bytes);
  }

  Uint8List? getPage(String bookId, int pageIndex) =>
      _pagesBox.get(_pageKey(bookId, pageIndex));

  bool hasPage(String bookId, int pageIndex) =>
      _pagesBox.containsKey(_pageKey(bookId, pageIndex));

  Future<void> deletePagesForBook(String bookId) async {
    final prefix = '${bookId}_';
    final keys = _pagesBox.keys.where((k) => (k as String).startsWith(prefix));
    await _pagesBox.deleteAll(keys);
  }

  /// Total bytes downloaded for every book belonging to [seriesId].
  int sizeForSeries(String seriesId) {
    final bookIds = listTasks()
        .where((t) => t.seriesId == seriesId)
        .map((t) => t.bookId)
        .toSet();
    var total = 0;
    for (final key in _pagesBox.keys) {
      final bookId = (key as String).split('_').first;
      if (bookIds.contains(bookId)) {
        total += _pagesBox.get(key)?.lengthInBytes ?? 0;
      }
    }
    return total;
  }

  int get totalSize {
    var total = 0;
    for (final bytes in _pagesBox.values) {
      total += bytes.lengthInBytes;
    }
    return total;
  }

  Future<void> clearSeries(String seriesId) async {
    final bookIds =
        listTasks().where((t) => t.seriesId == seriesId).map((t) => t.bookId).toList();
    for (final bookId in bookIds) {
      await deletePagesForBook(bookId);
      await deleteTask(bookId);
    }
  }

  Future<void> clearAll() async {
    await _pagesBox.clear();
    await _tasksBox.clear();
  }

  bool get wifiOnly => _settingsBox.get(_wifiOnlyKey) == 'true';

  Future<void> setWifiOnly(bool value) =>
      _settingsBox.put(_wifiOnlyKey, value.toString());
}
