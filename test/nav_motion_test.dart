// The tab capsule must glide to the tapped tab over several frames, not
// snap - guards the "I don't see any animation" regression.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shaddai_reader/app/providers.dart';
import 'package:shaddai_reader/app/router.dart';
import 'package:shaddai_reader/app/theme.dart';
import 'package:shaddai_reader/core/appearance/appearance_settings.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';

void main() {
  testWidgets('tab capsule glides instead of snapping', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeServerIdProvider.overrideWith((ref) => null),
          recentReadingProvider.overrideWithValue(const []),
          currentUsernameProvider.overrideWith((ref) => null),
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

    double capsuleX() => tester.getTopLeft(find
        .descendant(
            of: find.byType(AnimatedPositioned),
            matching: find.byType(DecoratedBox))
        .first).dx;

    final start = capsuleX();
    await tester.tap(find.text('Settings').last);
    await tester.pump(); // frame 0 of the animation
    await tester.pump(const Duration(milliseconds: 60));
    final mid = capsuleX();
    await tester.pumpAndSettle();
    final end = capsuleX();

    expect(end, greaterThan(start));
    expect(mid, greaterThan(start), reason: 'capsule did not start moving');
    expect(mid, lessThan(end), reason: 'capsule jumped straight to the end');
  });
}
