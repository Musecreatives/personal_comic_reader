import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/core/reader/reader_settings.dart';
import 'package:shaddai_reader/features/reader/widgets/reader_settings_sheet.dart';

Future<void> _open(WidgetTester tester) async {
  // Phone-sized, where the sheet's content is taller than the screen.
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => ReaderSettingsSheet.show(
            context,
            settings: const ReaderSettings(),
            rememberForSeries: false,
            onChanged: (_) {},
            onRememberChanged: (_) {},
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.text('Reader settings'), findsOneWidget);
}

void main() {
  testWidgets('Done closes the reader settings sheet', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Reader settings'), findsNothing);
  });

  testWidgets('dragging the sheet down closes it', (tester) async {
    await _open(tester);
    await tester.drag(find.text('Reader settings'), const Offset(0, 700));
    await tester.pumpAndSettle();
    expect(find.text('Reader settings'), findsNothing);
  });

  testWidgets('leaves a strip of backdrop above it to tap', (tester) async {
    await _open(tester);
    await tester.tapAt(const Offset(195, 20));
    await tester.pumpAndSettle();
    expect(find.text('Reader settings'), findsNothing);
  });
}
