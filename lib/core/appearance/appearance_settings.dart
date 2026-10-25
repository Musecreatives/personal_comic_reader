import 'package:flutter/material.dart';

import '../../app/platform_style.dart';

/// Names are what's saved, so they stay: `paper` is shown as Washi and
/// `trueBlack` as OLED black (DESIGN.md "Theme modes").
enum AppThemeMode { midnight, trueBlack, paper, system }

extension AppThemeModeResolve on AppThemeMode {
  /// The palette actually drawn: System follows the device's light/dark
  /// setting, picking Washi or Midnight.
  AppThemeMode resolve(Brightness platform) => this != AppThemeMode.system
      ? this
      : (platform == Brightness.light ? AppThemeMode.paper : AppThemeMode.midnight);
}

/// Accent options offered in the picker (DESIGN.md "Accent options"). The
/// accent is the colour of what you press; seal red is separate and fixed.
enum AccentOption { purple, aiIndigo, matcha, yamabuki, hanko }

extension AccentOptionColor on AccentOption {
  Color get color => switch (this) {
        AccentOption.purple => const Color(0xFF6E56CF),
        AccentOption.aiIndigo => const Color(0xFF2E5E9E),
        AccentOption.matcha => const Color(0xFF3D7A52),
        AccentOption.yamabuki => const Color(0xFFB87410),
        AccentOption.hanko => const Color(0xFFD23B3F),
      };
}

/// Saved accent names from before the brand change map to their nearest
/// new option; anything unknown falls back to violet.
AccentOption _accentFromName(String? name) => switch (name) {
      'komgaBlue' => AccentOption.aiIndigo,
      'suwayomiGreen' => AccentOption.matcha,
      'kavitaAmber' => AccentOption.yamabuki,
      'danger' => AccentOption.hanko,
      _ => AccentOption.values.asNameMap()[name] ?? AccentOption.purple,
    };

class AppearanceSettings {
  final AppThemeMode themeMode;
  final AccentOption accent;

  /// Per device, never synced: a Windows PC and an iPhone on the same
  /// account each keep their own (see [AppearanceStore]).
  final InterfaceStyle interfaceStyle;

  const AppearanceSettings({
    this.themeMode = AppThemeMode.midnight,
    this.accent = AccentOption.purple,
    this.interfaceStyle = InterfaceStyle.auto,
  });

  AppearanceSettings copyWith({
    AppThemeMode? themeMode,
    AccentOption? accent,
    InterfaceStyle? interfaceStyle,
  }) =>
      AppearanceSettings(
        themeMode: themeMode ?? this.themeMode,
        accent: accent ?? this.accent,
        interfaceStyle: interfaceStyle ?? this.interfaceStyle,
      );

  @override
  bool operator ==(Object other) =>
      other is AppearanceSettings &&
      other.themeMode == themeMode &&
      other.accent == accent &&
      other.interfaceStyle == interfaceStyle;

  @override
  int get hashCode => Object.hash(themeMode, accent, interfaceStyle);

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'accent': accent.name,
      };

  factory AppearanceSettings.fromJson(Map<String, dynamic> json) => AppearanceSettings(
        themeMode: AppThemeMode.values.asNameMap()[json['themeMode']] ?? AppThemeMode.midnight,
        accent: _accentFromName(json['accent'] as String?),
      );
}
