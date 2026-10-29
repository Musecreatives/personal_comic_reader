import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/appearance/appearance_settings.dart';
import 'platform_style.dart';

/// Design tokens from the "Reading Now & Downloads" design package
/// (2026-08 UI/UX pass), reconfigurable at runtime by the Appearance
/// screen (6b). Fields are mutable statics rather than a passed-down
/// object so every screen can keep reading `AppColors.x` directly; call
/// [AppColors.configure] once when appearance changes and rebuild the
/// widget tree under a changed key so everything re-reads the new values
/// (see `main.dart`).
class AppColors {
  AppColors._();

  static Color accent = const Color(0xFF6E56CF);
  static Color accentHover = const Color(0xFF7D67D9);
  static Color accentLink = const Color(0xFF8F7BEA);
  static Color accentSoft = const Color(0xFFB7A6F5);

  static Color page = const Color(0xFF0A1420);
  static Color canvas = const Color(0xFF07101B);
  static Color card = const Color(0xFF111F31);
  static Color border = const Color(0xFF1E3350);
  static Color borderStrong = const Color(0xFF223349);

  static Color text = const Color(0xFFF4F3F7);
  static Color textAlt = const Color(0xFFF3F6FA);
  static Color text60 = const Color(0xFFF3F6FA).withValues(alpha: 0.60);
  static Color text45 = const Color(0xFFF3F6FA).withValues(alpha: 0.45);
  static Color text42 = const Color(0xFFF3F6FA).withValues(alpha: 0.42);
  static Color text30 = const Color(0xFFF3F6FA).withValues(alpha: 0.30);

  static Color fillSubtle = const Color(0xFF8FC1E8).withValues(alpha: 0.10);
  static Color fillHover = const Color(0xFF8FC1E8).withValues(alpha: 0.06);
  static Color track = const Color(0xFF8FC1E8).withValues(alpha: 0.18);

  // Backend brand identity colors - fixed regardless of theme/accent, since
  // these mark a specific external service, not app chrome.
  static const komga = Color(0xFF2E75C4);
  static const komgaText = Color(0xFF8FC1E8);
  static const kavita = Color(0xFFC9821F);
  static const kavitaText = Color(0xFFE0A24E);
  static const kavitaOnDark = Color(0xFFE7C395);
  static const suwayomi = Color(0xFF149E7C);
  static const suwayomiText = Color(0xFF4FD1A9);
  static const kapowarr = Color(0xFFC9821F);
  // Crimson, kept clear of seal red; always shown with an icon and a label.
  // `danger` fills, `dangerText` is the theme-aware text/stroke shade.
  static const danger = Color(0xFFC92A5A);
  static Color dangerText = const Color(0xFFFF6F93);

  // Hanko seal ink: the logo, stamps, the cover corner mark. Identity only,
  // never a control, and fixed whatever accent is picked (the design system).
  static Color seal = const Color(0xFFD23B3F);
  static Color sealText = const Color(0xFFFF8588);
  static const onSeal = Color(0xFFFFF8F5);

  /// The palette actually drawn for [settings]: System resolves to Washi
  /// or Midnight from the device's current light/dark setting.
  static AppThemeMode resolvedMode(AppearanceSettings settings) => settings
      .themeMode
      .resolve(WidgetsBinding.instance.platformDispatcher.platformBrightness);
  // Something is down but nothing is wrong with you or your data (a server
  // not answering): amber, as on the canvas "offline" and "outage" boards.
  // Danger red stays for things you must fix, like a rejected login.
  static const warning = Color(0xFFC9821F);
  static const warningText = Color(0xFFE0A24E);

  static const coverTints = [
    Color(0xFF2D2145),
    Color(0xFF12303A),
    Color(0xFF12294A),
    Color(0xFF242A50),
    Color(0xFF3A2130),
    Color(0xFF1B2C46),
    Color(0xFF123A33),
  ];

  static Color sourceColor(String backendType) {
    switch (backendType.toLowerCase()) {
      case 'komga':
        return komga;
      case 'kavita':
        return kavita;
      case 'suwayomi':
        return suwayomi;
      default:
        return text45;
    }
  }

  /// Recomputes every token for [settings]. Called once by main.dart
  /// whenever the Appearance screen changes theme mode or accent, right
  /// before the app rebuilds under a new key.
  static void configure(AppearanceSettings settings) {
    PlatformStyle.configure(settings.interfaceStyle);
    final mode = resolvedMode(settings);
    final light = mode == AppThemeMode.paper;
    // On paper the accent darkens a step so it keeps its contrast
    // (violet #6E56CF becomes about #5B45B8).
    accent = light
        ? Color.lerp(settings.accent.color, Colors.black, 0.15)!
        : settings.accent.color;
    accentHover = Color.lerp(accent, light ? Colors.black : Colors.white, 0.12)!;
    accentLink = Color.lerp(accent, light ? Colors.black : Colors.white, 0.22)!;
    accentSoft = Color.lerp(accent, light ? Colors.black : Colors.white, 0.42)!;
    seal = light ? const Color(0xFFC9302F) : const Color(0xFFD23B3F);
    sealText = light ? const Color(0xFFB3261E) : const Color(0xFFFF8588);
    dangerText = light ? const Color(0xFFA3123F) : const Color(0xFFFF6F93);

    switch (mode) {
      case AppThemeMode.midnight:
        page = const Color(0xFF0A1420);
        canvas = const Color(0xFF07101B);
        card = const Color(0xFF111F31);
        border = const Color(0xFF1E3350);
        borderStrong = const Color(0xFF223349);
        text = const Color(0xFFF4F3F7);
        textAlt = const Color(0xFFF3F6FA);
        text60 = textAlt.withValues(alpha: 0.60);
        text45 = textAlt.withValues(alpha: 0.45);
        text42 = textAlt.withValues(alpha: 0.42);
        text30 = textAlt.withValues(alpha: 0.30);
        fillSubtle = const Color(0xFF8FC1E8).withValues(alpha: 0.10);
        fillHover = const Color(0xFF8FC1E8).withValues(alpha: 0.06);
        track = const Color(0xFF8FC1E8).withValues(alpha: 0.18);
      case AppThemeMode.trueBlack:
        page = Colors.black;
        canvas = Colors.black;
        card = const Color(0xFF0D0D0D);
        border = const Color(0xFF262626);
        borderStrong = const Color(0xFF303030);
        text = const Color(0xFFF4F3F7);
        textAlt = const Color(0xFFF3F6FA);
        text60 = textAlt.withValues(alpha: 0.60);
        text45 = textAlt.withValues(alpha: 0.45);
        text42 = textAlt.withValues(alpha: 0.42);
        text30 = textAlt.withValues(alpha: 0.30);
        fillSubtle = Colors.white.withValues(alpha: 0.06);
        fillHover = Colors.white.withValues(alpha: 0.04);
        track = Colors.white.withValues(alpha: 0.14);
      // Washi (the design system): cool paper, black ink.
      case AppThemeMode.paper:
      case AppThemeMode.system:
        page = const Color(0xFFF3F3F1);
        canvas = const Color(0xFFDADAD4);
        card = const Color(0xFFE7E7E3);
        border = const Color(0x29141519);
        borderStrong = const Color(0x52141519);
        text = const Color(0xFF141519);
        textAlt = const Color(0xFF141519);
        text60 = textAlt.withValues(alpha: 0.62);
        text45 = textAlt.withValues(alpha: 0.48);
        text42 = textAlt.withValues(alpha: 0.45);
        text30 = textAlt.withValues(alpha: 0.32);
        fillSubtle = Colors.black.withValues(alpha: 0.05);
        fillHover = Colors.black.withValues(alpha: 0.035);
        track = Colors.black.withValues(alpha: 0.12);
    }
  }
}

/// M PLUS 1 Code is used for every piece of metadata (counts, sizes,
/// latency, status words, section labels) - see the design system "Typography".
/// It also covers kana and kanji, so Japanese series titles in metadata
/// render in the same face.
class AppText {
  AppText._();

  static TextStyle sectionLabel({Color? color}) => GoogleFonts.mPlus1Code(
        fontSize: 9.5,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.4, // ~.1em at 9.5px
        color: color ?? AppColors.text42,
      );

  static TextStyle mono({
    double size = 11,
    FontWeight weight = FontWeight.w500,
    Color? color,
  }) =>
      GoogleFonts.mPlus1Code(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.text45,
      );

  /// The platform's text face (see [PlatformStyle.fontFamily]).
  static TextStyle _face({
    required double size,
    required FontWeight weight,
    required Color color,
    double? letterSpacing,
    double? height,
  }) {
    final family = PlatformStyle.fontFamily;
    if (family == null) {
      return GoogleFonts.zenKakuGothicNew(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );
    }
    return TextStyle(
      fontFamily: family,
      fontFamilyFallback: PlatformStyle.fontFallback,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) =>
      _face(size: size, weight: weight, color: color ?? AppColors.text);

  static TextStyle heading({
    double size = 20,
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) =>
      _face(
        size: size,
        // Callers ask for bold; each platform renders its own title weight.
        weight: weight == FontWeight.w700 ? PlatformStyle.titleWeight : weight,
        letterSpacing: PlatformStyle.titleTracking(size),
        color: color ?? AppColors.text,
        height: 1.1,
      );

  /// Page and hero titles: an iOS large title, a Material 3 headline or a
  /// Fluent title depending on the platform.
  static TextStyle largeTitle({double size = 30, Color? color}) => _face(
        size: size,
        weight: PlatformStyle.titleWeight,
        letterSpacing: PlatformStyle.titleTracking(size),
        height: 1.05,
        color: color ?? AppColors.text,
      );
}

/// Cover placeholder: a flat tint (no gradients, the design system), used until a
/// real thumbnail loads (or as a fallback when a series has none).
BoxDecoration coverPlaceholderDecoration(int seed) {
  final tint = AppColors.coverTints[seed % AppColors.coverTints.length];
  return BoxDecoration(color: tint);
}
