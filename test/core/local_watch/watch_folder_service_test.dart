import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:shaddai_reader/backends/local/local_library_store.dart';
import 'package:shaddai_reader/core/local_watch/watch_folder_service.dart';
import 'package:shaddai_reader/core/local_watch/watch_folder_store.dart';

Uint8List _fakeCbz() {
  final archive = Archive()..addFile(ArchiveFile.string('1.jpg', 'x' * 10));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  setUp(() async => await setUpTestHive());
  tearDown(() async => await tearDownTestHive());

  late LocalLibraryStore libraryStore;
  late WatchFolderStore watchStore;
  late Directory dir;
  var importedCount = 0;

  setUp(() async {
    libraryStore = LocalLibraryStore();
    await libraryStore.init();
    watchStore = WatchFolderStore();
    await watchStore.init();
    dir = Directory.systemTemp.createTempSync('watch_folder_test');
    importedCount = 0;
  });

  tearDown(() => dir.deleteSync(recursive: true));

  WatchFolderService buildService() => WatchFolderService(
        libraryStore: libraryStore,
        watchStore: watchStore,
        onImported: () => importedCount++,
      );

  test('imports a CBZ already sitting in the folder on start()', () async {
    File('${dir.path}/chapter1.cbz').writeAsBytesSync(_fakeCbz());
    await watchStore.setPath(dir.path);

    await buildService().start();
    // The service waits 2s per entry before importing (lets a copy finish).
    await Future.delayed(const Duration(seconds: 3));

    expect(importedCount, 1);
    expect(libraryStore.listSeries(), hasLength(1));
  });

  test('does not re-import an entry already marked seen', () async {
    File('${dir.path}/chapter1.cbz').writeAsBytesSync(_fakeCbz());
    // Mark it seen using the exact path dir.list() will yield (OS-native
    // separators), not the forward-slash path used to construct the file -
    // they must match for hasSeen() to work.
    final realPath = dir.listSync().single.path;
    await watchStore.markSeen(realPath);
    await watchStore.setPath(dir.path);

    await buildService().start();
    await Future.delayed(const Duration(seconds: 3));

    expect(importedCount, 0);
    expect(libraryStore.listSeries(), isEmpty);
  });
}
