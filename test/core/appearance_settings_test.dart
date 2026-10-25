import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/core/appearance/appearance_settings.dart';

void main() {
  test('settings saved before the brand change still load', () {
    AppearanceSettings load(String mode, String accent) =>
        AppearanceSettings.fromJson({'themeMode': mode, 'accent': accent});

    expect(load('midnight', 'purple').accent, AccentOption.purple);
    expect(load('paper', 'komgaBlue').accent, AccentOption.aiIndigo);
    expect(load('trueBlack', 'suwayomiGreen').accent, AccentOption.matcha);
    expect(load('midnight', 'kavitaAmber').accent, AccentOption.yamabuki);
    expect(load('midnight', 'danger').accent, AccentOption.hanko);
    expect(load('paper', 'danger').themeMode, AppThemeMode.paper);
    // Anything unknown falls back instead of throwing.
    expect(load('neon', 'chartreuse').themeMode, AppThemeMode.midnight);
    expect(load('neon', 'chartreuse').accent, AccentOption.purple);
  });

  test('System resolves to Washi by day and Midnight by night', () {
    expect(AppThemeMode.system.resolve(Brightness.light), AppThemeMode.paper);
    expect(AppThemeMode.system.resolve(Brightness.dark), AppThemeMode.midnight);
    expect(AppThemeMode.trueBlack.resolve(Brightness.light), AppThemeMode.trueBlack);
  });
}
