import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../../app/platform_style.dart';

import '../sync/resource_sync.dart';
import 'appearance_settings.dart';

/// Persists the user's theme mode + accent color choice (6b Appearance),
/// synced across devices, and the interface style, which stays on this
/// device in a box of its own (every entry in the synced box is pushed).
class AppearanceStore {
  static const _boxName = 'appearance_settings';
  static const _deviceBoxName = 'appearance_device';
  static const _key = 'settings';
  static const _styleKey = 'interfaceStyle';

  late final Box<String> _box;
  late final Box<String> _deviceBox;
  final sync = ResourceSync('appearance');

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
    _deviceBox = await Hive.openBox<String>(_deviceBoxName);
  }

  Future<bool> reconcile() => sync.reconcile(_box);

  AppearanceSettings get() {
    final raw = _box.get(_key);
    final synced = raw == null
        ? const AppearanceSettings()
        : AppearanceSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    final style = InterfaceStyle.values
            .where((s) => s.name == _deviceBox.get(_styleKey))
            .firstOrNull ??
        InterfaceStyle.auto;
    return synced.copyWith(interfaceStyle: style);
  }

  Future<void> set(AppearanceSettings settings) async {
    await _deviceBox.put(_styleKey, settings.interfaceStyle.name);
    await sync.put(_box, _key, settings.toJson());
  }
}
