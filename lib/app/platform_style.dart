import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Which platform's conventions the chrome follows: navigation, bars,
/// sheets, dialogs, controls, transitions and type. The brand (colours,
/// covers, the reader itself) stays the same everywhere; only the frame
/// around it changes. See the design system "Platforms".
enum UiPlatform { ios, android, windows, web }

/// The user's choice in Appearance. [auto] follows the device; the rest
/// force one style, mostly so each can be checked from any build.
enum InterfaceStyle { auto, ios, android, windows, web }

extension InterfaceStyleLabel on InterfaceStyle {
  String get label => switch (this) {
        InterfaceStyle.auto => 'Automatic',
        InterfaceStyle.ios => 'iOS',
        InterfaceStyle.android => 'Android',
        InterfaceStyle.windows => 'Windows',
        InterfaceStyle.web => 'Web',
      };
}

/// The resolved style, set once per appearance change alongside
/// [AppColors.configure] (main.dart) so widgets can read it statically the
/// same way they read colours.
class PlatformStyle {
  PlatformStyle._();

  static UiPlatform current = resolve(InterfaceStyle.auto);

  static void configure(InterfaceStyle style) => current = resolve(style);

  static UiPlatform resolve(InterfaceStyle style) => switch (style) {
        InterfaceStyle.ios => UiPlatform.ios,
        InterfaceStyle.android => UiPlatform.android,
        InterfaceStyle.windows => UiPlatform.windows,
        InterfaceStyle.web => UiPlatform.web,
        InterfaceStyle.auto => _device(),
      };

  static UiPlatform _device() {
    // An installed PWA on a phone is still a web app: it has a browser's
    // back button, no native sheets and no system font guarantees.
    if (kIsWeb) return UiPlatform.web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => UiPlatform.ios,
      TargetPlatform.windows => UiPlatform.windows,
      _ => UiPlatform.android,
    };
  }

  static bool get isIOS => current == UiPlatform.ios;
  static bool get isAndroid => current == UiPlatform.android;
  static bool get isWindows => current == UiPlatform.windows;
  static bool get isWeb => current == UiPlatform.web;

  /// Pointer-first platforms: hover states, tighter density, visible
  /// scrollbars, keyboard focus rings.
  static bool get isDesktopLike => isWindows || isWeb;

  /// What `.adaptive` Material widgets and scroll physics should follow.
  /// Web keeps the browser's own OS so touch scrolling still feels right
  /// on a phone.
  static TargetPlatform get targetPlatform => switch (current) {
        UiPlatform.ios => TargetPlatform.iOS,
        UiPlatform.android => TargetPlatform.android,
        UiPlatform.windows => TargetPlatform.windows,
        UiPlatform.web => defaultTargetPlatform,
      };

  /// Text face for everything except metadata (which is always JetBrains
  /// Mono). Each platform gets its system face; web uses Zen Kaku Gothic New
  /// (the design system) because a browser guarantees no particular font. Null means
  /// that face. A forced style in a web build keeps it too, since the browser has none of
  /// the system faces to hand.
  static String? get fontFamily => kIsWeb ? null : switch (current) {
        UiPlatform.ios => 'CupertinoSystemText',
        UiPlatform.android => 'Roboto',
        UiPlatform.windows => 'Segoe UI Variable Text',
        UiPlatform.web => null,
      };

  static List<String> get fontFallback => switch (current) {
        UiPlatform.ios => const ['.SF Pro Text', 'Roboto', 'sans-serif'],
        UiPlatform.android => const ['sans-serif'],
        UiPlatform.windows => const ['Segoe UI', 'sans-serif'],
        UiPlatform.web => const ['sans-serif'],
      };

  /// Weight and tracking of titles. iOS large titles are bold and tight,
  /// Material 3 headlines medium and untracked, Fluent titles semibold.
  static FontWeight get titleWeight => switch (current) {
        UiPlatform.ios || UiPlatform.web => FontWeight.w700,
        UiPlatform.android => FontWeight.w500,
        UiPlatform.windows => FontWeight.w600,
      };

  static double titleTracking(double size) => switch (current) {
        UiPlatform.ios || UiPlatform.web => -0.02 * size,
        UiPlatform.android || UiPlatform.windows => 0,
      };

  /// Corner radius of dialogs: iOS alert, Material 3, Fluent ContentDialog.
  static double get dialogRadius => switch (current) {
        UiPlatform.ios => 14,
        UiPlatform.android => 28,
        UiPlatform.windows => 8,
        UiPlatform.web => 16,
      };

  /// Corner radius of buttons, fields and list rows on the platform.
  static double get controlRadius => switch (current) {
        UiPlatform.ios => 12,
        UiPlatform.android => 20,
        UiPlatform.windows => 4,
        UiPlatform.web => 10,
      };
}

/// Width breakpoints shared by the shell and pages (Material window size
/// classes, which Fluent's NavigationView thresholds sit close to).
class Breakpoints {
  Breakpoints._();

  /// Below this: phone, bottom navigation. From here: a side rail or
  /// compact pane.
  static const compact = 600.0;

  /// From here: expanded (two-pane, wider) content layouts.
  static const expanded = 1008.0;

  /// From here the Windows and web sidebar shows its labels; below it the
  /// pane stays compact so a tablet-width window keeps its canvas for the
  /// covers.
  static const sidebar = 1280.0;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compact;
}
