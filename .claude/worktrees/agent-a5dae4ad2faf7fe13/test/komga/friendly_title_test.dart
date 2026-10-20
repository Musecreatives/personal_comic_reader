import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/backends/komga/komga_backend.dart';

void main() {
  // Paths are the real layout of the library: /data/comics/<Series>/Volume NN (YYYY)/
  test('a bare volume folder name becomes the parent series plus year', () {
    expect(
      friendlySeriesTitle('Volume 01 (2025)',
          'file:/data/comics/Absolute%20Batman/Volume%2001%20(2025)/'),
      'Absolute Batman (2025)',
    );
  });

  test('later volumes keep their number', () {
    expect(
      friendlySeriesTitle(
          'Volume 06 (2019)', 'file:/data/comics/X-Men/Volume%2006%20(2019)/'),
      'X-Men Vol. 6 (2019)',
    );
  });

  test('special characters in the parent folder survive decoding', () {
    expect(
      friendlySeriesTitle('Volume 01 (2019)',
          "file:/data/comics/Uncanny%20X-Men%20-%20Winter's%20End/Volume%2001%20(2019)/"),
      "Uncanny X-Men - Winter's End (2019)",
    );
  });

  test('a real title from metadata is left alone', () {
    expect(
      friendlySeriesTitle(
          'X-Men (2019)', 'file:/data/comics/X-Men/Volume%2006%20(2019)/'),
      'X-Men (2019)',
    );
  });

  test('no url or no parent folder falls back to the given title', () {
    expect(friendlySeriesTitle('Volume 01 (2025)', null), 'Volume 01 (2025)');
    expect(friendlySeriesTitle('Volume 01 (2025)', 'file:/Volume%2001%20(2025)/'),
        'Volume 01 (2025)');
  });
}
