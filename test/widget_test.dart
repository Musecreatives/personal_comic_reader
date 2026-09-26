// Smoke test: the app boots to the "no server configured" empty state
// via the real router when there's no active backend, without throwing.
//
// Deliberately overrides activeServerIdProvider/activeBackendProvider
// directly rather than exercising real Hive/ServerStore - a real Hive
// box needs platform channels that flutter_test's unit-test environment
// doesn't provide, which hung this test indefinitely. Storage itself is
// covered separately by ServerStore usage in the app; this test's job is
// just to prove the router + theme + HomeScreen wiring doesn't throw.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shaddai_reader/app/providers.dart';
import 'package:shaddai_reader/app/router.dart';
import 'package:shaddai_reader/app/theme.dart';
import 'package:shaddai_reader/core/appearance/appearance_settings.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';

void main() {
  testWidgets('shows empty state when no server is configured',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeServerIdProvider.overrideWith((ref) => null),
          recentReadingProvider.overrideWithValue(const []),
          activeBackendProvider
              .overrideWith((ref) async => null as ReaderBackend?),
        ],
        child: MaterialApp.router(
          theme: buildAppTheme(const AppearanceSettings()),
          routerConfig: buildRouter(),
        ),
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );

    expect(find.text('No server configured'), findsOneWidget);
    expect(find.text('Add a server'), findsOneWidget);
  });

  // The nav shell has two layouts (floating bar on phones, side rail on wide
  // screens) - both must build, show all five tabs, and switch tabs cleanly.
  for (final size in const [Size(390, 844), Size(1600, 900)]) {
    testWidgets('nav shell builds and switches tabs at ${size.width.toInt()}px',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeServerIdProvider.overrideWith((ref) => null),
            recentReadingProvider.overrideWithValue(const []),
            activeBackendProvider
                .overrideWith((ref) async => null as ReaderBackend?),
          ],
          child: MaterialApp.router(
            theme: buildAppTheme(const AppearanceSettings()),
            routerConfig: buildRouter(),
          ),
        ),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );

      for (final label in ['Home', 'Search', 'Library', 'History', 'Settings']) {
        expect(find.text(label), findsWidgets, reason: '$label tab missing');
      }

      await tester.tap(find.text('Search').last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Search across every server'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
