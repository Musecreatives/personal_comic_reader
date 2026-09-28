import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/core/downloads/download_models.dart';

void main() {
  test('reordering a failed task keeps its error; retrying clears it', () {
    const failed = DownloadTask(
      bookId: 'b',
      seriesId: 's',
      seriesTitle: 'S',
      title: 'T',
      totalPages: 3,
      state: DownloadState.failed,
      error: 'boom',
    );
    expect(failed.copyWith(order: 5).error, 'boom');
    expect(failed.copyWith(state: DownloadState.queued).error, isNull);
  });
}
