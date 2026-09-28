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

/// Windows' built-in bsdtar, when present - what the importer shells out to
/// for RAR/7z. Only used here to *create* a 7z fixture.
String? get _windowsTar {
  if (!Platform.isWindows) return null;
  final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
  final tar = '$root\\System32\\tar.exe';
  return File(tar).existsSync() ? tar : null;
}

void main() {
  // Every behaviour must hold whether pages live as files (desktop/mobile)
  // or in a Hive box (web).
  for (final fileBacked in [true, false]) {
    group(fileBacked ? 'file-backed pages' : 'Hive-backed pages', () {
      late LocalLibraryStore store;
      late Directory work;

      setUp(() async {
        await setUpTestHive();
        work = Directory.systemTemp.createTempSync('local_import_test');
        store = LocalLibraryStore(
          pagesDir: fileBacked ? Directory('${work.path}/pages') : null,
        );
        await store.init();
      });

      tearDown(() async {
        await tearDownTestHive();
        work.deleteSync(recursive: true);
      });

      test('imports every image page in natural order', () async {
        final bytes =
            _fakeCbz(['page2.jpg', 'page10.jpg', 'page1.jpg', 'notes.txt']);
        final bookId = await importArchive(
          store: store,
          fileName: 'Blood Hunt Diaries (2024) (Digital) (Shan-Empire).cbz',
          bytes: bytes,
        );

        final book = store.getBook(bookId)!;
        expect(book.pageCount, 3); // notes.txt excluded
        expect(book.title, 'Blood Hunt Diaries');
        for (var i = 0; i < 3; i++) {
          expect(await store.getPage(bookId, i), isNotNull);
        }
      });

      test('skips macOS resource-fork shadows', () async {
        final bytes = _fakeCbz(['1.jpg', '__MACOSX/._1.jpg', '._2.jpg']);
        final bookId =
            await importArchive(store: store, fileName: 'x.cbz', bytes: bytes);
        expect(store.getBook(bookId)!.pageCount, 1);
      });

      test('strips bracket tags from the guessed title', () async {
        final bookId = await importArchive(
          store: store,
          fileName: 'Blood Hunt Diaries (2024) (Digital) (Shan-Empire).cbz',
          bytes: _fakeCbz(['1.jpg']),
        );
        final book = store.getBook(bookId)!;
        expect(store.getSeries(book.seriesId)!.title, 'Blood Hunt Diaries');
      });

      test('a second import with a matching title joins the same series',
          () async {
        final book1 = await importArchive(
          store: store,
          fileName: 'One World Under Doom (2025) #1.cbz',
          bytes: _fakeCbz(['1.jpg']),
          seriesTitle: 'One World Under Doom',
        );
        final book2 = await importArchive(
          store: store,
          fileName: 'One World Under Doom (2025) #2.cbz',
          bytes: _fakeCbz(['1.jpg']),
          seriesTitle: 'One World Under Doom',
        );

        final b1 = store.getBook(book1)!;
        expect(b1.seriesId, store.getBook(book2)!.seriesId);
        expect(store.listSeries(), hasLength(1));
        expect(store.listBooksForSeries(b1.seriesId), hasLength(2));
      });

      test('chapters sort numerically, so 10 comes after 2', () async {
        for (final n in ['10', '2', '1']) {
          await importArchive(
            store: store,
            fileName: 'Ch $n.cbz',
            bytes: _fakeCbz(['1.jpg']),
            seriesTitle: 'Series',
            chapterNumber: n,
          );
        }
        final seriesId = store.listSeries().single.id;
        expect(store.listBooksForSeries(seriesId).map((b) => b.number),
            ['1', '2', '10']);
      });

      test('rejects an archive with no image pages', () async {
        final archive = Archive()
          ..addFile(ArchiveFile.string('readme.txt', 'hi'));
        final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
        expect(
          () => importArchive(store: store, fileName: 'empty.cbz', bytes: bytes),
          throwsA(isA<ImportException>()),
        );
      });

      test('in-memory import of a RAR (the web path) says to use desktop',
          () async {
        final bytes =
            Uint8List.fromList([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]);
        expect(
          () => importArchive(store: store, fileName: 'a.cbr', bytes: bytes),
          throwsA(isA<ImportException>()
              .having((e) => e.message, 'message', contains('desktop'))),
        );
      });

      test('importArchiveFile reads a CBZ straight from disk', () async {
        final cbz = File('${work.path}/Chapter 5.cbz')
          ..writeAsBytesSync(_fakeCbz(['2.jpg', '1.jpg']));

        final bookId = await importArchiveFile(store: store, path: cbz.path);

        final book = store.getBook(bookId)!;
        expect(book.pageCount, 2);
        expect(book.title, 'Chapter 5');
        expect(cbz.existsSync(), isTrue, reason: 'source is left alone');
      });

      test('importArchiveFile unpacks a non-ZIP archive with the OS tar',
          () async {
        final tar = _windowsTar;
        final src = Directory('${work.path}/src')..createSync();
        File('${src.path}/p2.jpg').writeAsBytesSync([2]);
        File('${src.path}/p1.jpg').writeAsBytesSync([1]);
        final archive = '${work.path}/Issue 1.cb7';
        final made = await Process.run(
            tar!, ['--format', '7zip', '-cf', archive, '-C', src.path, '.']);
        expect(made.exitCode, 0, reason: '${made.stderr}');

        final bookId = await importArchiveFile(store: store, path: archive);

        final book = store.getBook(bookId)!;
        expect(book.title, 'Issue 1');
        expect(await store.getPage(bookId, 0), [1]);
        expect(await store.getPage(bookId, 1), [2]);
      }, skip: _windowsTar == null ? 'needs Windows tar.exe' : false);

      test('deleteBook removes its pages and the emptied series', () async {
        final bookId = await importArchive(
            store: store, fileName: 'x.cbz', bytes: _fakeCbz(['1.jpg']));
        await store.deleteBook(bookId);
        expect(await store.getPage(bookId, 0), isNull);
        expect(store.listSeries(), isEmpty);
      });

      group('export', () {
        test('exportBookToCbz round-trips pages byte-for-byte', () async {
          final bookId = await importArchive(
              store: store,
              fileName: 'Test.cbz',
              bytes: _fakeCbz(['1.jpg', '2.jpg', '3.jpg']));
          final book = store.getBook(bookId)!;

          final archive =
              ZipDecoder().decodeBytes(await exportBookToCbz(store, book));

          expect(archive.files, hasLength(3));
          for (var i = 0; i < 3; i++) {
            expect(await store.getPage(bookId, i), archive.files[i].content);
          }
        });

        test('exportBookToCbzFile writes a readable CBZ to disk', () async {
          final bookId = await importArchive(
              store: store,
              fileName: 'Test.cbz',
              bytes: _fakeCbz(['1.jpg', '2.jpg']));
          final out = '${work.path}/out.cbz';

          await exportBookToCbzFile(store, store.getBook(bookId)!, out);

          final archive = ZipDecoder().decodeBytes(File(out).readAsBytesSync());
          expect(archive.files.map((f) => f.name), ['0001.jpg', '0002.jpg']);
          expect(archive.files[1].content, await store.getPage(bookId, 1));
        });

        test('exportSeriesToFolder writes one CBZ per chapter', () async {
          final book1 = await importArchive(
            store: store,
            fileName: 'One World Under Doom #1.cbz',
            bytes: _fakeCbz(['1.jpg']),
            seriesTitle: 'One World Under Doom',
          );
          await importArchive(
            store: store,
            fileName: 'One World Under Doom #2.cbz',
            bytes: _fakeCbz(['1.jpg']),
            seriesTitle: 'One World Under Doom',
          );

          final count = await exportSeriesToFolder(
            store: store,
            seriesId: store.getBook(book1)!.seriesId,
            folderPath: work.path,
          );

          expect(count, 2);
          final seriesDir = Directory('${work.path}/One World Under Doom');
          expect(seriesDir.listSync().whereType<File>(), hasLength(2));
        });
      });

      group('importFolder', () {
        late Directory dir;
        setUp(() => dir = Directory('${work.path}/folder')..createSync());

        test('imports every image in natural order, ignoring non-images',
            () async {
          File('${dir.path}/page2.jpg').writeAsBytesSync([1, 2, 3]);
          File('${dir.path}/page10.jpg').writeAsBytesSync([4, 5, 6]);
          File('${dir.path}/page1.jpg').writeAsBytesSync([7, 8, 9]);
          File('${dir.path}/notes.txt').writeAsStringSync('hi');

          final bookId = await importFolder(store: store, folderPath: dir.path);

          expect(store.getBook(bookId)!.pageCount, 3);
          expect(await store.getPage(bookId, 0), [7, 8, 9]); // page1
          expect(await store.getPage(bookId, 1), [1, 2, 3]); // page2
          expect(await store.getPage(bookId, 2), [4, 5, 6]); // page10
          expect(File('${dir.path}/page1.jpg').existsSync(), isTrue,
              reason: "the user's folder is copied from, not moved");
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
        test('imports selected images in natural order', () async {
          final bookId = await importLooseFiles(
            store: store,
            chapterTitle: 'Some Chapter',
            files: [
              PickedImageFile('page2.jpg', Uint8List.fromList([1])),
              PickedImageFile('page1.jpg', Uint8List.fromList([2])),
            ],
          );

          expect(store.getBook(bookId)!.pageCount, 2);
          expect(await store.getPage(bookId, 0), [2]); // page1
          expect(await store.getPage(bookId, 1), [1]); // page2
        });

        test('rejects an empty selection', () async {
          expect(
            () => importLooseFiles(store: store, chapterTitle: 'x', files: []),
            throwsA(isA<ImportException>()),
          );
        });
      });
    });
  }
}
