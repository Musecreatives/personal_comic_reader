import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shaddai_reader/core/backend/models.dart';
import 'package:shaddai_reader/features/series/download_sheet.dart';

Book book(int n, {bool completed = false, int? page}) => Book(
      id: 'b$n',
      seriesId: 's',
      title: 'Chapter $n',
      number: '$n',
      pageCount: 20,
      readProgressPage: page,
      completed: completed,
    );

void main() {
  // 1-2 read, 3 half way through, 4-8 unread; chapter 8 is already queued.
  final books = [
    book(1, completed: true),
    book(2, completed: true),
    book(3, page: 9),
    for (var i = 4; i <= 8; i++) book(i),
  ];

  Future<List<String>?> pick(WidgetTester tester, String option) async {
    List<Book>? chosen;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => DownloadSheet.show(
              context,
              books: books,
              alreadyIds: {'b8'},
              onConfirm: (c) async => chosen = c,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option));
    await tester.pumpAndSettle();
    return chosen?.map((b) => b.id).toList();
  }

  testWidgets('Next 5 starts at the chapter you are on and skips queued ones',
      (tester) async {
    expect(await pick(tester, 'Next 5'), ['b3', 'b4', 'b5', 'b6', 'b7']);
  });

  testWidgets('New since you last read excludes the one in progress',
      (tester) async {
    expect(await pick(tester, 'New since you last read'),
        ['b4', 'b5', 'b6', 'b7']);
  });

  testWidgets('Everything includes read chapters but not queued ones',
      (tester) async {
    expect(await pick(tester, 'Everything'),
        ['b1', 'b2', 'b3', 'b4', 'b5', 'b6', 'b7']);
  });
}
