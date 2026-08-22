import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'reader_settings.dart';

/// Persists the global default [ReaderSettings] and per-series overrides.
///
/// A series only has an entry here if the user explicitly opted into
/// "remember these settings" for it; otherwise [effective] falls back to
/// the global default.
class ReaderSettingsStore {
  static const _boxName = 'reader_settings';
  static const _globalKey = 'global';

  late final Box<String> _box;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  ReaderSettings getGlobal() {
    final raw = _box.get(_globalKey);
    if (raw == null) return const ReaderSettings();
    return ReaderSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> setGlobal(ReaderSettings settings) {
    return _box.put(_globalKey, jsonEncode(settings.toJson()));
  }

  ReaderSettings? getForSeries(String seriesId) {
    final raw = _box.get(_seriesKey(seriesId));
    if (raw == null) return null;
    return ReaderSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> setForSeries(String seriesId, ReaderSettings settings) {
    return _box.put(_seriesKey(seriesId), jsonEncode(settings.toJson()));
  }

  Future<void> clearForSeries(String seriesId) {
    return _box.delete(_seriesKey(seriesId));
  }

  bool hasOverride(String seriesId) => _box.containsKey(_seriesKey(seriesId));

  /// The settings that should actually apply to [seriesId]: its override if
  /// one was saved, otherwise the global default.
  ReaderSettings effective(String seriesId) =>
      getForSeries(seriesId) ?? getGlobal();

  String _seriesKey(String seriesId) => 'series_$seriesId';
}
