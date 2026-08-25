import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens from the "Reading Now & Downloads" design package
/// (2026-08 UI/UX pass). Colors, type and spacing here are the source of
/// truth for new screens; existing screens migrate onto these gradually.
class AppColors {
  AppColors._();

  static const accent = Color(0xFF6E56CF);
  static const accentHover = Color(0xFF7D67D9);
  static const accentLink = Color(0xFF8F7BEA);
  static const accentSoft = Color(0xFFB7A6F5);

  static const page = Color(0xFF0A1420);
  static const canvas = Color(0xFF07101B);
  static const card = Color(0xFF111F31);
  static const border = Color(0xFF1E3350);
  static const borderStrong = Color(0xFF223349);

  static const text = Color(0xFFF4F3F7);
  static const textAlt = Color(0xFFF3F6FA);
  static Color text60 = const Color(0xFFF3F6FA).withValues(alpha: 0.60);
  static Color text45 = const Color(0xFFF3F6FA).withValues(alpha: 0.45);
  static Color text42 = const Color(0xFFF3F6FA).withValues(alpha: 0.42);
  static Color text30 = const Color(0xFFF3F6FA).withValues(alpha: 0.30);

  static Color fillSubtle = const Color(0xFF8FC1E8).withValues(alpha: 0.10);
  static Color fillHover = const Color(0xFF8FC1E8).withValues(alpha: 0.06);
  static Color track = const Color(0xFF8FC1E8).withValues(alpha: 0.18);

  static const komga = Color(0xFF2E75C4);
  static const komgaText = Color(0xFF8FC1E8);
  static const kavita = Color(0xFFC9821F);
  static const kavitaText = Color(0xFFE0A24E);
  static const kavitaOnDark = Color(0xFFE7C395);
  static const suwayomi = Color(0xFF149E7C);
  static const suwayomiText = Color(0xFF4FD1A9);
  static const kapowarr = Color(0xFFC9821F);
  static const danger = Color(0xFFD8455F);
  static const dangerText = Color(0xFFE8798D);

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
}

/// JetBrains Mono is used for every piece of metadata (counts, sizes,
/// latency, status words, section labels) - see README "Typography".
class AppText {
  AppText._();

  static TextStyle sectionLabel({Color? color}) => GoogleFonts.jetBrainsMono(
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
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.text45,
      );

  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.text,
      );

  static TextStyle heading({
    double size = 20,
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: -0.4,
        color: color ?? AppColors.text,
        height: 1.1,
      );

  /// iOS large-title style, used for the hero title on 3a.
  static TextStyle largeTitle({double size = 30, Color? color}) => TextStyle(
        fontFamily: 'CupertinoSystemText',
        fontFamilyFallback: const ['.SF Pro Text', 'Roboto', 'sans-serif'],
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        height: 1.05,
        color: color ?? AppColors.text,
      );
}

/// Cover-placeholder gradient recipe from the design package, used until a
/// real thumbnail loads (or as a fallback when a series has none).
BoxDecoration coverPlaceholderDecoration(int seed) {
  final tint = AppColors.coverTints[seed % AppColors.coverTints.length];
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [tint, const Color(0xFF0C1A2B)],
    ),
  );
}
