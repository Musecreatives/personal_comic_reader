import 'dart:io';
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

  group('importFolder', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('local_import_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('imports every image file in natural order, ignoring non-images',
        () async {
      File('${dir.path}/page2.jpg').writeAsBytesSync([1, 2, 3]);
      File('${dir.path}/page10.jpg').writeAsBytesSync([4, 5, 6]);
      File('${dir.path}/page1.jpg').writeAsBytesSync([7, 8, 9]);
      File('${dir.path}/notes.txt').writeAsStringSync('hi');

      final bookId = await importFolder(store: store, folderPath: dir.path);

      final book = store.getBook(bookId)!;
      expect(book.pageCount, 3);
      expect(store.getPage(bookId, 0), [7, 8, 9]); // page1
      expect(store.getPage(bookId, 1), [1, 2, 3]); // page2
      expect(store.getPage(bookId, 2), [4, 5, 6]); // page10
    });

    test('rejects a folder with no image files', () async {
      File('${dir.path}/notes.txt').writeAsStringSync('hi');
      expect(
        () => importFolder(store: store, folderPath: dir.path),
        throwsA(isA<ImportException>()),
      );
    });

    test('rejects a missing folder', () async {
      expect(
        () => importFolder(store: store, folderPath: '${dir.path}/nope'),
        throwsA(isA<ImportException>()),
      );
    });
  });

  group('importLooseFiles', () {
    test('imports selected images in natural order under the given title',
        () async {
      final bookId = await importLooseFiles(
        store: store,
        chapterTitle: 'Some Chapter',
        files: [
          PickedImageFile('page2.jpg', Uint8List.fromList([1])),
          PickedImageFile('page1.jpg', Uint8List.fromList([2])),
        ],
      );

      final book = store.getBook(bookId)!;
      expect(book.pageCount, 2);
      expect(store.getPage(bookId, 0), [2]); // page1
      expect(store.getPage(bookId, 1), [1]); // page2
    });

    test('rejects an empty selection', () async {
      expect(
        () => importLooseFiles(store: store, chapterTitle: 'x', files: []),
        throwsA(isA<ImportException>()),
      );
    });
  });
}
