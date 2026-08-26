import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/connectivity_banner.dart';
import 'app/providers.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/downloads/download_manager.dart';
import 'core/downloads/download_store.dart';
import 'core/kapowarr/kapowarr_config_store.dart';
import 'core/reader/page_cache.dart';
import 'core/reader/progress_sync.dart';
import 'core/reader/reader_settings_store.dart';
import 'core/stats/reading_stats_store.dart';
import 'core/storage/last_route_store.dart';
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

  final downloadStore = DownloadStore();
  await downloadStore.init();
  final downloadManager = DownloadManager(store: downloadStore);

  final pageCache = PageCache(downloadStore: downloadStore);
  await pageCache.init();

  final kapowarrConfigStore = KapowarrConfigStore();
  await kapowarrConfigStore.init();

  final readingStatsStore = ReadingStatsStore();
  await readingStatsStore.init();

  final lastRouteStore = LastRouteStore();
  final lastRoute = await lastRouteStore.getLastRoute();
  final defaultLocation =
      serverStore.listServers().isEmpty ? '/onboarding' : '/home';
  final router = buildRouter(
    initialLocation: lastRoute ?? defaultLocation,
    onRouteChange: lastRouteStore.setLastRoute,
  );

  runApp(
    ProviderScope(
      overrides: [
        serverStoreProvider.overrideWithValue(serverStore),
        readerSettingsStoreProvider.overrideWithValue(readerSettingsStore),
        progressSyncProvider.overrideWithValue(progressSync),
        pageCacheProvider.overrideWithValue(pageCache),
        kapowarrConfigStoreProvider.overrideWithValue(kapowarrConfigStore),
        downloadStoreProvider.overrideWithValue(downloadStore),
        downloadManagerProvider.overrideWithValue(downloadManager),
        readingStatsStoreProvider.overrideWithValue(readingStatsStore),
      ],
      child: ShaddaiReaderApp(router: router),
    ),
  );
}

class ShaddaiReaderApp extends StatelessWidget {
  final GoRouter router;
  const ShaddaiReaderApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Shaddai Reader',
      theme: buildAppTheme(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          ConnectivityBanner(child: child ?? const SizedBox.shrink()),
    );
  }
}
