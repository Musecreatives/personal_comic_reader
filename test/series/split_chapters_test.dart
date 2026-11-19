import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/core/backend/models.dart';
import 'package:shaddai_reader/features/series/download_sheet.dart';

Book _ch(String number) => Book(
      id: 'c$number',
      seriesId: 's',
      title: 'Ch. $number',
      number: number,
      pageCount: 1,
      completed: false,
    );

void main() {
  test('only parts of a chapter that also exists whole are split', () {
    final books = ['11', '12', '12.1', '12.2', '13.5', '14', 'extra'].map(_ch).toList();
    // 13.5 stays: there is no whole 13, so it is the only copy.
    expect(splitChapterIds(books), {'c12.1', 'c12.2'});
  });

  test('a series without split chapters has none', () {
    expect(splitChapterIds(['1', '2', '3'].map(_ch).toList()), isEmpty);
  });
}
