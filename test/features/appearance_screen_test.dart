import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shaddai_reader/app/design_tokens.dart';
import 'package:shaddai_reader/app/providers.dart';
import 'package:shaddai_reader/app/theme.dart';
import 'package:shaddai_reader/core/appearance/appearance_settings.dart';
import 'package:shaddai_reader/features/settings/appearance_screen.dart';

void main() {
  // The tablet's logical sizes (landscape, portrait) plus a phone.
  const sizes = [Size(1101, 688), Size(688, 1101), Size(390, 844)];

  for (final mode in [AppThemeMode.paper, AppThemeMode.system]) {
    for (final size in sizes) {
      testWidgets('Appearance lays out in ${mode.name} at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final settings = AppearanceSettings(themeMode: mode, accent: AccentOption.hanko);
        AppColors.configure(settings);
        await tester.pumpWidget(ProviderScope(
          overrides: [appearanceProvider.overrideWith((ref) => settings)],
          child: MaterialApp(theme: buildAppTheme(settings), home: const AppearanceScreen()),
        ));
        await tester.pump();

        expect(tester.takeException(), isNull);
        for (final label in ['Midnight', 'Washi', 'OLED', 'System']) {
          expect(find.text(label), findsOneWidget);
        }
      });
    }
  }
}
