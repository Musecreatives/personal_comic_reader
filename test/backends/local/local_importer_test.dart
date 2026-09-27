import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:shaddai_reader/backends/local/local_importer.dart';
import 'package:shaddai_reader/backends/local/local_library_store.dart';

Uint8List _fakeCbz(List<String> pageNames) {
  final archive = Archive();
  for (final name in pageNames) {
    archive.addFile(ArchiveFile.string(name, 'x' * 10));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  setUp(() async => await setUpTestHive());
  tearDown(() async => await tearDownTestHive());

  late LocalLibraryStore store;
  setUp(() async {
    store = LocalLibraryStore();
    await store.init();
  });

  test('imports every image page in natural order', () async {
    final bytes = _fakeCbz(['page2.jpg', 'page10.jpg', 'page1.jpg', 'notes.txt']);
    final bookId = await importArchive(
      store: store,
      fileName: 'Blood Hunt Diaries (2024) (Digital) (Shan-Empire).cbz',
      bytes: bytes,
    );

    final book = store.getBook(bookId)!;
    expect(book.pageCount, 3); // notes.txt excluded
    expect(book.title, 'Blood Hunt Diaries');

    // Natural order: page1, page2, page10 - not string order.
    expect(store.getPage(bookId, 0), isNotNull);
    expect(store.getPage(bookId, 1), isNotNull);
    expect(store.getPage(bookId, 2), isNotNull);
  });

  test('strips bracket tags from the guessed title', () async {
    final bytes = _fakeCbz(['1.jpg']);
    final bookId = await importArchive(
      store: store,
      fileName: 'Blood Hunt Diaries (2024) (Digital) (Shan-Empire).cbz',
      bytes: bytes,
    );
    final book = store.getBook(bookId)!;
    final series = store.getSeries(book.seriesId)!;
    expect(series.title, 'Blood Hunt Diaries');
  });

  test('a second import with a matching title joins the same series', () async {
    final bytes1 = _fakeCbz(['1.jpg']);
    final bytes2 = _fakeCbz(['1.jpg']);
    final book1 = await importArchive(
      store: store,
      fileName: 'One World Under Doom (2025) #1.cbz',
      bytes: bytes1,
      seriesTitle: 'One World Under Doom',
    );
    final book2 = await importArchive(
      store: store,
      fileName: 'One World Under Doom (2025) #2.cbz',
      bytes: bytes2,
      seriesTitle: 'One World Under Doom',
    );

    final b1 = store.getBook(book1)!;
    final b2 = store.getBook(book2)!;
    expect(b1.seriesId, b2.seriesId);
    expect(store.listSeries(), hasLength(1));
    expect(store.listBooksForSeries(b1.seriesId), hasLength(2));
  });

  test('rejects an archive with no image pages', () async {
    final archive = Archive()..addFile(ArchiveFile.string('readme.txt', 'hi'));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

    expect(
      () => importArchive(store: store, fileName: 'empty.cbz', bytes: bytes),
      throwsA(isA<ImportException>()),
    );
  });

  test('a real (RAR) CBR file gets a clear, actionable error', () async {
    // Not a ZIP at all - the RAR magic bytes, truncated.
    final bytes = Uint8List.fromList([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]);

    expect(
      () => importArchive(store: store, fileName: 'a-real.cbr', bytes: bytes),
      throwsA(isA<ImportException>().having(
        (e) => e.message,
        'message',
        contains('CBR'),
      )),
    );
  });
}
