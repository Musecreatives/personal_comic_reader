import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/providers.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/kapowarr/kapowarr_config_store.dart';
import 'core/reader/page_cache.dart';
import 'core/reader/progress_sync.dart';
import 'core/reader/reader_settings_store.dart';
import 'core/storage/server_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  final serverStore = ServerStore();
  await serverStore.init();

  final readerSettingsStore = ReaderSettingsStore();
  await readerSettingsStore.init();

  final progressSync = ProgressSync();
  await progressSync.init();

  final pageCache = PageCache();
  await pageCache.init();

  final kapowarrConfigStore = KapowarrConfigStore();
  await kapowarrConfigStore.init();

  runApp(
    ProviderScope(
      overrides: [
        serverStoreProvider.overrideWithValue(serverStore),
        readerSettingsStoreProvider.overrideWithValue(readerSettingsStore),
        progressSyncProvider.overrideWithValue(progressSync),
        pageCacheProvider.overrideWithValue(pageCache),
        kapowarrConfigStoreProvider.overrideWithValue(kapowarrConfigStore),
      ],
      child: const ShaddaiReaderApp(),
    ),
  );
}

class ShaddaiReaderApp extends StatelessWidget {
  const ShaddaiReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Shaddai Reader',
      theme: buildAppTheme(),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
