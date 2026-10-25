import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/appearance/appearance_settings.dart';
import 'design_tokens.dart';
import 'platform_style.dart';

/// Builds the Material theme from the user's [AppearanceSettings] (6b).
/// Call [AppColors.configure] with the same settings first (main.dart does
/// this before every rebuild) so the two stay in sync - this only handles
/// the parts of the app that go through `Theme.of(context)` rather than
/// reading `AppColors` directly.
///
/// The brand is shared; the conventions follow [PlatformStyle.current]:
/// iOS slide-and-swipe-back with press scaling, Android predictive back
/// with ripples, Windows' fade-forward entrance with hover fills, web
/// fades with hover fills. `platform` is set too, so `.adaptive` widgets
/// (switches, dialogs, indicators) and scroll physics follow the same
/// choice, including when the style is forced in Appearance.
ThemeData buildAppTheme(AppearanceSettings appearance) {
  final isLight = AppColors.resolvedMode(appearance) == AppThemeMode.paper;
  final p = PlatformStyle.current;

  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: isLight ? Brightness.light : Brightness.dark,
  ).copyWith(
    primary: AppColors.accent,
    surface: AppColors.page,
    surfaceContainerLowest: AppColors.canvas,
    surfaceContainerLow: AppColors.card,
    surfaceContainer: AppColors.card,
    surfaceContainerHigh: AppColors.card,
    surfaceContainerHighest: Color.lerp(AppColors.card, AppColors.text, 0.06),
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.text60,
    outline: AppColors.borderStrong,
    outlineVariant: AppColors.border,
  );

  final darkBase = ThemeData.dark().textTheme;
  final lightBase = ThemeData.light().textTheme;
  final family = PlatformStyle.fontFamily;
  final baseTextTheme = family == null
      ? (isLight
          ? GoogleFonts.interTextTheme(lightBase)
          : GoogleFonts.interTextTheme(darkBase))
      : (isLight ? lightBase : darkBase).apply(
          fontFamily: family,
          fontFamilyFallback: PlatformStyle.fontFallback,
        );

  final transition = switch (p) {
    UiPlatform.ios => const CupertinoPageTransitionsBuilder(),
    UiPlatform.android => const PredictiveBackPageTransitionsBuilder(),
    UiPlatform.windows => const FadeForwardsPageTransitionsBuilder(),
    UiPlatform.web => const FadeForwardsPageTransitionsBuilder(),
  };

  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(PlatformStyle.controlRadius),
  );
  final dialogShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(PlatformStyle.dialogRadius),
    side: p == UiPlatform.windows
        ? BorderSide(color: AppColors.border)
        : BorderSide.none,
  );

  return ThemeData(
    useMaterial3: true,
    platform: PlatformStyle.targetPlatform,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.page,
    canvasColor: AppColors.page,
    visualDensity: PlatformStyle.isDesktopLike
        ? VisualDensity.compact
        : VisualDensity.standard,
    materialTapTargetSize: PlatformStyle.isDesktopLike
        ? MaterialTapTargetSize.shrinkWrap
        : MaterialTapTargetSize.padded,
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      for (final t in TargetPlatform.values) t: transition,
    }),
    // Ripples are Android's touch feedback. iOS presses in (PressScale);
    // Windows and the web answer with hover and pressed fills.
    splashFactory: p == UiPlatform.android
        ? InkSparkle.splashFactory
        : NoSplash.splashFactory,
    highlightColor: AppColors.fillHover,
    hoverColor: AppColors.fillHover,
    focusColor: AppColors.accent.withValues(alpha: 0.18),
    textTheme: baseTextTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    iconTheme: IconThemeData(color: AppColors.text),
    dividerTheme: DividerThemeData(color: AppColors.border, space: 1),
    appBarTheme: AppBarTheme(
      centerTitle: p == UiPlatform.ios,
      backgroundColor: AppColors.page,
      foregroundColor: AppColors.text,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(p == UiPlatform.windows ? 8 : 16),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      shape: dialogShape,
      titleTextStyle: AppText.heading(size: p == UiPlatform.windows ? 20 : 19),
      contentTextStyle: AppText.body(color: AppColors.text60),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: AppColors.card,
      // Material and iOS sheets both carry a grabber; desktop sheets are
      // shown as dialogs instead (see showAppSheet).
      showDragHandle: p == UiPlatform.android,
      dragHandleColor: AppColors.text30,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(p == UiPlatform.android ? 28 : 16)),
      ),
      constraints: const BoxConstraints(maxWidth: 640),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        shape: p == UiPlatform.ios ? const StadiumBorder() : controlShape,
        textStyle: AppText.body(weight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: BorderSide(color: AppColors.borderStrong),
        shape: p == UiPlatform.ios ? const StadiumBorder() : controlShape,
        textStyle: AppText.body(weight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accentLink,
        shape: controlShape,
        textStyle: AppText.body(weight: FontWeight.w600),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? Colors.white : AppColors.text60),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColors.accent : AppColors.track),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.track,
      circularTrackColor: AppColors.track,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: AppColors.track,
      thumbColor: AppColors.accent,
    ),
    // Desktop shows scrollbars like any desktop app; touch platforms keep
    // the system's transient ones.
    scrollbarTheme: ScrollbarThemeData(
      thumbVisibility: WidgetStateProperty.all(PlatformStyle.isDesktopLike),
      thickness: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.hovered) ? 8 : 4),
      thumbColor: WidgetStateProperty.all(AppColors.text30),
      radius: const Radius.circular(8),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(PlatformStyle.isWindows ? 4 : 8),
        border: Border.all(color: AppColors.border),
      ),
      textStyle: AppText.body(size: 12),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.card,
      contentTextStyle: AppText.body(size: 13.5),
      actionTextColor: AppColors.accentLink,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PlatformStyle.controlRadius),
        side: BorderSide(color: AppColors.border),
      ),
      width: PlatformStyle.isDesktopLike ? 420 : null,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      // Canvas "Android · Home": violet pill, filled white icon, bold label.
      indicatorColor: AppColors.accent.withValues(alpha: 0.32),
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => AppText.body(
            size: 12,
            weight: s.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: s.contains(WidgetState.selected)
                ? AppColors.text
                : AppColors.text60,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected)
                ? AppColors.text
                : AppColors.text60,
          )),
    ),
    // Canvas "Android tablet · Home": 96 wide, same pill as the bar.
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: AppColors.canvas,
      minWidth: 96,
      indicatorColor: AppColors.accent.withValues(alpha: 0.32),
      selectedIconTheme: IconThemeData(color: AppColors.text),
      unselectedIconTheme: IconThemeData(color: AppColors.text60),
      selectedLabelTextStyle:
          AppText.body(size: 12, weight: FontWeight.w700),
      unselectedLabelTextStyle:
          AppText.body(size: 12, weight: FontWeight.w500, color: AppColors.text60),
    ),
  );
}
