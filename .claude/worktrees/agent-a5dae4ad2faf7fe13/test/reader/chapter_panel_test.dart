import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/core/backend/models.dart';
import 'package:shaddai_reader/features/reader/widgets/chapter_panel.dart';

Book _book(int n, {bool completed = false}) => Book(
      id: 'b$n',
      seriesId: 's',
      title: 'Chapter $n',
      number: '$n',
      pageCount: 20,
      completed: completed,
    );

void main() {
  testWidgets('lists every chapter and opens the one you click', (tester) async {
    Book? opened;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: ChapterPanel.width,
          child: ChapterPanel(
            title: 'Demo Series',
            books: [_book(1, completed: true), _book(2), _book(3)],
            currentId: 'b2',
            onOpen: (b) => opened = b,
            onClose: () {},
          ),
        ),
      ),
    ));

    expect(find.text('Demo Series'), findsOneWidget);
    expect(find.text('Chapter 1'), findsOneWidget);
    expect(find.text('Chapter 3'), findsOneWidget);

    // The chapter you're on does nothing; another one opens.
    await tester.tap(find.text('Chapter 2'));
    expect(opened, isNull);
    await tester.tap(find.text('Chapter 3'));
    expect(opened?.id, 'b3');
  });
}
