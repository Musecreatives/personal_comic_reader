// The launch splash plays its whole 2.7s at phone and tablet sizes without
// a layout error (an overflow throws in tests), and then gets out of the way.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/app/brand_seal.dart';

void main() {
  for (final size in const [Size(390, 844), Size(1280, 800), Size(800, 1280), Size(1101, 688)]) {
    testWidgets('splash plays cleanly at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      LaunchSplash.reset();

      await tester.pumpWidget(const MaterialApp(
        home: LaunchSplash(child: Scaffold(body: Text('app'))),
      ));
      expect(find.text('Shaddai Reader'), findsNothing); // the first script first
      for (var ms = 0; ms <= 2800; ms += 100) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: 'at ${ms}ms');
      }
      await tester.pumpAndSettle();
      expect(find.text('app'), findsOneWidget);
      expect(find.text('Shaddai Reader'), findsNothing); // the splash has gone
    });
  }
}
