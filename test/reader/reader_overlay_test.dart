import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shaddai_reader/core/reader/reader_settings.dart';
import 'package:shaddai_reader/features/reader/widgets/reader_overlay.dart';

void main() {
  Widget host({
    required bool visible,
    ValueChanged<int>? onSeek,
    VoidCallback? onClose,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            ReaderOverlay(
              visible: visible,
              title: 'Chapter 8',
              subtitle: 'Ch. 8',
              currentPage: 0,
              pageCount: 10,
              settings: const ReaderSettings(),
              onSeek: onSeek ?? (_) {},
              onClose: onClose ?? () {},
              onOpenSettings: () {},
              onToggleDirection: () {},
              onCycleMode: () {},
              onOpenChapters: () {},
            ),
          ]),
        ),
      );

  testWidgets('shows a quiet page counter when the chrome is hidden',
      (tester) async {
    await tester.pumpWidget(host(visible: false));
    await tester.pumpAndSettle();

    final counter = tester.widget<Opacity>(find
        .ancestor(of: find.text('1 of 10'), matching: find.byType(Opacity))
        .first);
    expect(counter.opacity, 1);
  });

  testWidgets('scrubber jumps to the tapped position, close fires',
      (tester) async {
    int? sought;
    var closed = false;
    await tester.pumpWidget(host(
      visible: true,
      onSeek: (p) => sought = p,
      onClose: () => closed = true,
    ));
    await tester.pumpAndSettle();

    final scrubber = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Page 1 of 10');
    final box = tester.getRect(scrubber);
    await tester.tapAt(Offset(box.center.dx, box.bottom - 2));
    expect(sought, 9);

    await tester.tap(find.byTooltip('Close reader'));
    expect(closed, isTrue);
  });
}
