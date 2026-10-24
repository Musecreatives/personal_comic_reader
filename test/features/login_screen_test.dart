import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/app/providers.dart';
import 'package:shaddai_reader/core/sync/sync_client.dart';
import 'package:shaddai_reader/features/auth/login_screen.dart';

void main() {
  testWidgets('shows the sync server and lets it be changed', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncClientProvider.overrideWithValue(
              SyncClient(baseUrl: SyncClient.publicUrl)),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    expect(find.text('Sync server: reader.shaddaicommunications.com · Change'),
        findsOneWidget);

    await tester.tap(find.textContaining('Sync server:'));
    await tester.pump();

    expect(find.widgetWithText(TextField, 'Sync server'), findsOneWidget);
    expect(find.text(SyncClient.publicUrl), findsOneWidget);
  });
}
