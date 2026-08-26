import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'appearance_settings.dart';

/// Persists the user's theme mode + accent color choice (6b Appearance).
class AppearanceStore {
  static const _boxName = 'appearance_settings';
  static const _key = 'settings';

  late final Box<String> _box;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  AppearanceSettings get() {
    final raw = _box.get(_key);
    if (raw == null) return const AppearanceSettings();
    return AppearanceSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> set(AppearanceSettings settings) {
    return _box.put(_key, jsonEncode(settings.toJson()));
  }
}
