import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:shaddai_reader/app/providers.dart';
import 'package:shaddai_reader/core/downloads/download_manager.dart';
import 'package:shaddai_reader/core/downloads/download_store.dart';
import 'package:shaddai_reader/core/reader/page_cache.dart';
import 'package:shaddai_reader/features/downloads/storage_screen.dart';

void main() {
  late DownloadStore store;
  late PageCache cache;

  Widget screen() => ProviderScope(
        overrides: [
          downloadStoreProvider.overrideWithValue(store),
          pageCacheProvider.overrideWithValue(cache),
          downloadManagerProvider.overrideWithValue(DownloadManager(store: store)),
        ],
        child: const MaterialApp(home: StorageScreen()),
      );

  // Phone, and the tablet sizes CLAUDE.md asks for: overflow fails the test.
  for (final size in const [Size(390, 844), Size(1101, 688), Size(688, 1101)]) {
    testWidgets('Storage shows the reading cache and its limit at $size', (tester) async {
      await tester.runAsync(() async {
        await setUpTestHive();
        store = DownloadStore();
        await store.init();
        cache = PageCache();
        await cache.init();
        await cache.ready;
      });
      addTearDown(() => tester.runAsync(tearDownTestHive));
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(screen());
      await tester.pump();
      expect(find.text('Clear reading cache'), findsOneWidget);
      expect(find.text('Reading cache'), findsOneWidget);
      expect(find.text('Keep under 1 GB'), findsOneWidget);

      await tester.tap(find.text('Keep under 1 GB'));
      // Not pumpAndSettle: something on the screen keeps animating.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      for (final label in ['500 MB', '1 GB', '2 GB', '3 GB', '5 GB']) {
        expect(find.text(label), findsOneWidget);
      }
      // Picking a choice is covered by download_store_test (setLimit): its
      // real disk write can't finish inside this test's fake clock.
    });

    testWidgets('Storage shows a saved 3 GB limit at $size', (tester) async {
      await tester.runAsync(() async {
        await setUpTestHive();
        store = DownloadStore();
        await store.init();
        cache = PageCache();
        await cache.init();
        await cache.ready;
        await cache.setLimit(3 << 30);
      });
      addTearDown(() => tester.runAsync(tearDownTestHive));
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(screen());
      await tester.pump();
      expect(find.text('Keep under 3 GB'), findsOneWidget);
    });
  }
}
