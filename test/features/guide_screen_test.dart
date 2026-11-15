import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/features/onboarding/guide_screen.dart';

void main() {
  for (final size in const [Size(390, 844), Size(1101, 688), Size(688, 1101)]) {
    testWidgets('guide at ${size.width.toInt()}x${size.height.toInt()}: '
        'a step is done by doing it, every page fits', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: GuideScreen()));
      await tester.pumpAndSettle();

      // Step 1 isn't done until all five tabs have been tapped.
      expect(find.text('Skip this step'), findsOneWidget);
      for (final tab in const ['Home', 'Search', 'Library', 'History', 'Settings']) {
        await tester.tap(find.text(tab).last);
        await tester.pump();
      }
      expect(find.text('DONE'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      // Walk every step to the summary; nothing may overflow on the way.
      for (var i = 0; i < 8; i++) {
        final next = find.text('Next').evaluate().isNotEmpty
            ? find.text('Next')
            : find.text('Skip this step');
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(find.text('1 OF 8 TRIED'), findsOneWidget);
      expect(find.text('Start reading'), findsOneWidget);
    });
  }

  testWidgets('tapping the right of the page turns it', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GuideScreen()));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Skip this step'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Reading'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Next page'));
    await tester.tap(find.bySemanticsLabel('Show or hide the controls'));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(find.text('DONE'), findsOneWidget);
  });
}
