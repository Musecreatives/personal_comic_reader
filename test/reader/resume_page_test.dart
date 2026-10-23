import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/features/reader/reader_screen.dart';

void main() {
  test('the further of history and the server wins', () {
    // History stale (app killed mid-read): server is ahead.
    expect(resumePage(343, 443, 600), 443);
    // Server update still queued offline: history is ahead.
    expect(resumePage(450, 443, 600), 450);
    expect(resumePage(null, 443, 600), 443);
    expect(resumePage(null, null, 600), 0);
  });

  test('a page past the end opens on the last page, not the first', () {
    expect(resumePage(null, 600, 600), 599);
    expect(resumePage(5, null, 0), 0);
  });
}
