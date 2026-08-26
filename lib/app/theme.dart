import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/appearance/appearance_settings.dart';
import 'design_tokens.dart';

/// Builds the Material theme from the user's [AppearanceSettings] (6b).
/// Call [AppColors.configure] with the same settings first (main.dart does
/// this before every rebuild) so the two stay in sync - this only handles
/// the parts of the app that go through `Theme.of(context)` rather than
/// reading `AppColors` directly.
ThemeData buildAppTheme(AppearanceSettings appearance) {
  final isLight = appearance.themeMode == AppThemeMode.paper;

  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: isLight ? Brightness.light : Brightness.dark,
  ).copyWith(
    primary: AppColors.accent,
    surface: AppColors.page,
    surfaceContainerHigh: AppColors.card,
    outline: AppColors.border,
    outlineVariant: AppColors.border,
  );

  final baseTextTheme = isLight
      ? GoogleFonts.interTextTheme()
      : GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.page,
    textTheme: baseTextTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: AppColors.page,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.border),
      ),
    ),
  );
}
