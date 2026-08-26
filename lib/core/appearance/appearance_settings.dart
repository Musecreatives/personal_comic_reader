import 'package:flutter/material.dart';

enum AppThemeMode { midnight, trueBlack, paper }

/// Accent options offered in the picker - the app's own purple plus each
/// backend's identity color, matching the design package's ACCENT row.
enum AccentOption { purple, komgaBlue, suwayomiGreen, kavitaAmber, danger }

extension AccentOptionColor on AccentOption {
  Color get color => switch (this) {
        AccentOption.purple => const Color(0xFF6E56CF),
        AccentOption.komgaBlue => const Color(0xFF2E75C4),
        AccentOption.suwayomiGreen => const Color(0xFF149E7C),
        AccentOption.kavitaAmber => const Color(0xFFC9821F),
        AccentOption.danger => const Color(0xFFD8455F),
      };
}

class AppearanceSettings {
  final AppThemeMode themeMode;
  final AccentOption accent;

  const AppearanceSettings({
    this.themeMode = AppThemeMode.midnight,
    this.accent = AccentOption.purple,
  });

  AppearanceSettings copyWith({AppThemeMode? themeMode, AccentOption? accent}) =>
      AppearanceSettings(
        themeMode: themeMode ?? this.themeMode,
        accent: accent ?? this.accent,
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'accent': accent.name,
      };

  factory AppearanceSettings.fromJson(Map<String, dynamic> json) => AppearanceSettings(
        themeMode: AppThemeMode.values.byName(json['themeMode'] as String? ?? 'midnight'),
        accent: AccentOption.values.byName(json['accent'] as String? ?? 'purple'),
      );
}
