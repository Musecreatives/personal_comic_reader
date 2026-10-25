import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/app/providers.dart';
import 'package:shaddai_reader/core/appearance/appearance_settings.dart';
import 'package:shaddai_reader/core/sync/sync_client.dart';
import 'package:shaddai_reader/features/settings/settings_screen.dart';

void main() {
  Future<void> pumpSettings(WidgetTester tester, {required bool owner}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isOwnerProvider.overrideWith((ref) => owner),
          // Settings shows the theme mode beside Appearance.
          appearanceProvider.overrideWith((ref) => const AppearanceSettings()),
          // The live counts beside rows.
          downloadQueueProvider.overrideWith((ref) => Stream.value(const [])),
          readingStreakProvider.overrideWith((ref) => 0),
          collectionCountProvider.overrideWith((ref) => 0),
          currentUsernameProvider.overrideWith((ref) => 'someone'),
          syncClientProvider
              .overrideWithValue(SyncClient(baseUrl: SyncClient.publicUrl)),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
  }

  testWidgets('a friend does not see the owner tools', (tester) async {
    await pumpSettings(tester, owner: false);

    expect(find.text('Kapowarr'), findsNothing);
    expect(find.text('Suwayomi maintenance'), findsNothing);
    expect(find.text('Media Pool'), findsNothing);
    expect(find.text('Downloads'), findsOneWidget);
  });

  testWidgets('the owner sees everything', (tester) async {
    await pumpSettings(tester, owner: true);

    expect(find.text('Kapowarr'), findsOneWidget);
    expect(find.text('Suwayomi maintenance'), findsOneWidget);
    expect(find.text('Media Pool'), findsOneWidget);
  });
}
