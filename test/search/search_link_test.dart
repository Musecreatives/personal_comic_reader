import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/app/providers.dart';
import 'package:shaddai_reader/features/search/cross_server_search_screen.dart';

void main() {
  test('searchLocation encodes the title and the mode', () {
    final uri = Uri.parse(searchLocation('Return of the Mount Hua Sect & co', mode: 'manga'));
    expect(uri.path, '/search');
    expect(uri.queryParameters['q'], 'Return of the Mount Hua Sect & co');
    expect(uri.queryParameters['mode'], 'manga');
  });

  testWidgets('a search link prefills the query, and a new link replaces it',
      (tester) async {
    Widget app(String q) => ProviderScope(
          overrides: [allBackendsProvider.overrideWith((ref) async => [])],
          child: MaterialApp(
            home: CrossServerSearchScreen(initialQuery: q, initialMode: 'library'),
          ),
        );

    await tester.pumpWidget(app('One Piece'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'One Piece'), findsOneWidget);
    // Searched straight away: no backends, so the empty-servers message.
    expect(find.text('No servers configured.'), findsOneWidget);

    await tester.pumpWidget(app('Berserk'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Berserk'), findsOneWidget);
  });
}
