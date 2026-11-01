import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/backends/suwayomi/suwayomi_backend.dart';
import 'package:shaddai_reader/core/backend/models.dart';

void main() {
  group('carryProgress', () {
    test('marks everything up to the furthest finished chapter, gaps too', () {
      final carried = carryProgress(
        [
          (number: 1, read: true, page: 0),
          (number: 2, read: true, page: 0),
          // The old source skipped 2.5 and had 3 unread.
          (number: 3, read: false, page: 0),
        ],
        [
          (id: 10, number: 1),
          (id: 20, number: 2),
          (id: 25, number: 2.5),
          (id: 30, number: 3),
        ],
      );
      expect(carried.read, [10, 20]);
      expect(carried.pages, isEmpty);
    });

    test('a chapter read partway keeps its page on the new source', () {
      final carried = carryProgress(
        [
          (number: 181, read: true, page: 0),
          (number: 190, read: false, page: 8),
        ],
        [(id: 1, number: 181), (id: 2, number: 189), (id: 3, number: 190)],
      );
      expect(carried.read, [1]);
      expect(carried.pages, {3: 8});
    });

    test('chapter numbers match to one decimal place', () {
      final carried = carryProgress(
        [(number: 182.1, read: true, page: 0)],
        [(id: 7, number: 182.10000001), (id: 8, number: 182.2)],
      );
      expect(carried.read, [7]);
    });

    test('nothing read carries nothing', () {
      final carried = carryProgress(
        [(number: 1, read: false, page: 0)],
        [(id: 1, number: 1)],
      );
      expect(carried.read, isEmpty);
      expect(carried.pages, isEmpty);
    });
  });

  test('SeriesStatus.parse reads Komga and Suwayomi values', () {
    expect(SeriesStatus.parse('ONGOING'), SeriesStatus.ongoing);
    expect(SeriesStatus.parse('ENDED'), SeriesStatus.ended);
    expect(SeriesStatus.parse('COMPLETED'), SeriesStatus.ended);
    expect(SeriesStatus.parse('PUBLISHING_FINISHED'), SeriesStatus.ended);
    expect(SeriesStatus.parse('ON_HIATUS'), SeriesStatus.hiatus);
    expect(SeriesStatus.parse('hiatus'), SeriesStatus.hiatus);
    expect(SeriesStatus.parse('CANCELLED'), SeriesStatus.abandoned);
    expect(SeriesStatus.parse('UNKNOWN'), isNull);
    expect(SeriesStatus.parse(null), isNull);
  });
}
