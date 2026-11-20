import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hive_test/hive_test.dart';
import 'package:shaddai_reader/core/downloads/download_store.dart';
import 'package:shaddai_reader/core/reader/page_cache.dart';

void main() {
  setUp(() async => await setUpTestHive());
  tearDown(() async => await tearDownTestHive());

  test('pages saved by the old non-lazy store still open, read and count', () async {
    // What earlier versions left on the device: a plain box of page bytes.
    final old = await Hive.openBox<Uint8List>('download_pages');
    await old.put('b1_0', Uint8List(100));
    await old.put('b1_1', Uint8List(50));
    await old.close();

    final store = DownloadStore();
    await store.init();
    expect(store.hasPage('b1', 1), isTrue);
    expect((await store.getPage('b1', 0))!.length, 100);

    // Sizes of old pages are measured in the background after init.
    for (var i = 0; i < 50 && store.totalSize != 150; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(store.totalSize, 150);

    await store.putPage('b2', 0, Uint8List(7));
    expect(store.totalSize, 157);
    await store.deletePagesForBook('b1');
    expect(store.totalSize, 7);
    expect(store.hasPage('b1', 0), isFalse);
  });

  test('the page cache keeps at most diskCapacity pages on disk', () async {
    final box = await Hive.openBox<Uint8List>('page_cache');
    for (var i = 0; i < PageCache.diskCapacity + 30; i++) {
      await box.put('b_$i', Uint8List(1));
    }
    await box.close();

    await PageCache().init();
    final reopened = await Hive.openLazyBox<Uint8List>('page_cache');
    expect(reopened.length, PageCache.diskCapacity);
  });
}
