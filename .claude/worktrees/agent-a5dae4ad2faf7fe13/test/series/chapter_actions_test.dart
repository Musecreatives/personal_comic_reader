import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/features/series/chapter_actions.dart';

void main() {
  Widget bar({required int count, bool downloaded = false, void Function(ChapterAction)? onAction}) =>
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChapterSelectionBar(
              count: count,
              total: 10,
              anyDownloaded: downloaded,
              onAction: onAction ?? (_) {},
              onSelectAll: () {},
              onClear: () {},
            ),
          ),
        ),
      );

  testWidgets('shows the count and offers read/unread/download', (tester) async {
    await tester.pumpWidget(bar(count: 3));
    await tester.pumpAndSettle();

    expect(find.text('3 selected'), findsOneWidget);
    expect(find.byTooltip('Mark as read'), findsOneWidget);
    expect(find.byTooltip('Mark as unread'), findsOneWidget);
    expect(find.byTooltip('Download'), findsOneWidget);
    // Nothing downloaded in the selection: nothing to remove.
    expect(find.byTooltip('Remove download'), findsNothing);
  });

  testWidgets('remove download only appears when a selected chapter is downloaded',
      (tester) async {
    await tester.pumpWidget(bar(count: 2, downloaded: true));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove download'), findsOneWidget);
  });

  testWidgets('tapping an action reports it', (tester) async {
    ChapterAction? got;
    await tester.pumpWidget(bar(count: 2, onAction: (a) => got = a));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Mark as read'));
    expect(got, ChapterAction.markRead);
  });

  testWidgets('with nothing selected the bar is inert', (tester) async {
    ChapterAction? got;
    await tester.pumpWidget(bar(count: 0, onAction: (a) => got = a));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Mark as read'), warnIfMissed: false);
    expect(got, isNull);
  });
}
