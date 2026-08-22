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
import 'package:shaddai_reader/core/backend/reader_backend.dart';

void main() {
  testWidgets('shows empty state when no server is configured',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeServerIdProvider.overrideWith((ref) => null),
          activeBackendProvider
              .overrideWith((ref) async => null as ReaderBackend?),
        ],
        child: MaterialApp.router(
          theme: buildAppTheme(),
          routerConfig: appRouter,
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
}
