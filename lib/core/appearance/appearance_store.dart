import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../sync/resource_sync.dart';
import 'appearance_settings.dart';

/// Persists the user's theme mode + accent color choice (6b Appearance).
class AppearanceStore {
  static const _boxName = 'appearance_settings';
  static const _key = 'settings';

  late final Box<String> _box;
  final sync = ResourceSync('appearance');

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  Future<bool> reconcile() => sync.reconcile(_box);

  AppearanceSettings get() {
    final raw = _box.get(_key);
    if (raw == null) return const AppearanceSettings();
    return AppearanceSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> set(AppearanceSettings settings) {
    return sync.put(_box, _key, settings.toJson());
  }
}
