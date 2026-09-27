import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:shaddai_reader/backends/local/local_backend.dart';
import 'package:shaddai_reader/backends/local/local_importer.dart';
import 'package:shaddai_reader/backends/local/local_library_store.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';

Uint8List _fakeCbz(int pageCount) {
  final archive = Archive();
  for (var i = 0; i < pageCount; i++) {
    archive.addFile(ArchiveFile.string('$i.jpg', 'page-$i'));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  setUp(() async => await setUpTestHive());
  tearDown(() async => await tearDownTestHive());

  late LocalLibraryStore store;
  late LocalBackend backend;
  setUp(() async {
    store = LocalLibraryStore();
    await store.init();
    backend = LocalBackend(
      config: const ServerConfig(
        id: 'local',
        name: 'On This Device',
        type: ServerType.local,
        baseUrl: '',
        username: '',
      ),
      store: store,
    );
  });

  test('an imported book is listed, readable, and its pages match the file',
      () async {
    final bookId = await importArchive(
      store: store,
      fileName: 'Test Comic.cbz',
      bytes: _fakeCbz(3),
    );

    final series = (await backend.listSeries()).items.single;
    expect(series.title, 'Test Comic');
    expect(series.booksCount, 1);

    final book = await backend.getBook(bookId);
    expect(book.pageCount, 3);

    final page1 = await backend.fetchPage(bookId, 1);
    expect(String.fromCharCodes(page1), 'page-1');
  });

  test('progress written through the backend persists and marks completed',
      () async {
    final bookId = await importArchive(
      store: store,
      fileName: 'Test Comic.cbz',
      bytes: _fakeCbz(3),
    );

    await backend.updateProgress(bookId, page: 2, completed: true);

    final book = await backend.getBook(bookId);
    expect(book.readProgressPage, 2);
    expect(book.completed, isTrue);

    final series = (await backend.getSeries(book.seriesId));
    expect(series.isFullyRead, isTrue);
  });

  test('an in-progress (not completed) book surfaces via continueReading',
      () async {
    final bookId = await importArchive(
      store: store,
      fileName: 'Test Comic.cbz',
      bytes: _fakeCbz(3),
    );
    await backend.updateProgress(bookId, page: 1, completed: false);

    final continuing = await backend.continueReading();
    expect(continuing, hasLength(1));
    expect(continuing.single.title, 'Test Comic');
  });
}
