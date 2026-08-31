import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/connectivity_banner.dart';
import 'app/design_tokens.dart';
import 'app/providers.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/appearance/appearance_store.dart';
import 'core/collections/collections_store.dart';
import 'core/downloads/download_manager.dart';
import 'core/history/history_store.dart';
import 'core/downloads/download_store.dart';
import 'core/kapowarr/kapowarr_config_store.dart';
import 'core/reader/page_cache.dart';
import 'core/reader/progress_sync.dart';
import 'core/reader/reader_settings_store.dart';
import 'core/stats/reading_stats_store.dart';
import 'core/storage/last_route_store.dart';
import 'core/storage/server_store.dart';
import 'core/sync/auth_store.dart';
import 'core/sync/sync_client.dart';
import 'core/sync/sync_queue.dart';

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

  final appearanceStore = AppearanceStore();
  await appearanceStore.init();
  final initialAppearance = appearanceStore.get();
  AppColors.configure(initialAppearance);

  final historyStore = HistoryStore();
  await historyStore.init();

  final collectionsStore = CollectionsStore();
  await collectionsStore.init();

  final authStore = AuthStore();
  final syncToken = await authStore.getToken();
  final syncUsername = await authStore.getUsername();

  final syncQueue = SyncQueue();
  await syncQueue.init();

  final syncClient =
      SyncClient(baseUrl: SyncClient.defaultBaseUrl(), token: syncToken);

  if (syncToken != null) {
    historyStore.attachSync(syncClient, syncQueue);
    // Best-effort - don't block startup on a network round trip. Failures
    // just mean this device stays on what it already has locally until
    // the next successful reconcile (e.g. next app resume).
    unawaited(historyStore.reconcile());
  }

  final lastRouteStore = LastRouteStore();
  var lastRoute = await lastRouteStore.getLastRoute();
  // A saved route from a previous signed-in session (or /login itself)
  // shouldn't override the auth gate below in either direction.
  if (lastRoute == '/login') lastRoute = null;
  final defaultLocation =
      serverStore.listServers().isEmpty ? '/onboarding' : '/home';
  final initialLocation =
      syncToken == null ? '/login' : (lastRoute ?? defaultLocation);
  final router = buildRouter(
    initialLocation: initialLocation,
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
        appearanceStoreProvider.overrideWithValue(appearanceStore),
        appearanceProvider.overrideWith((ref) => initialAppearance),
        historyStoreProvider.overrideWithValue(historyStore),
        collectionsStoreProvider.overrideWithValue(collectionsStore),
        authStoreProvider.overrideWithValue(authStore),
        syncQueueProvider.overrideWithValue(syncQueue),
        syncClientProvider.overrideWithValue(syncClient),
        currentUsernameProvider.overrideWith((ref) => syncUsername),
      ],
      child: ShaddaiReaderApp(router: router),
    ),
  );
}

class ShaddaiReaderApp extends ConsumerWidget {
  final GoRouter router;
  const ShaddaiReaderApp({super.key, required this.router});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    // AppColors is a set of mutable statics (every screen reads them
    // directly rather than via Theme.of(context) for the design-package
    // surfaces) - resync them here, then key the subtree on the settings so
    // Flutter tears down and rebuilds every descendant from scratch instead
    // of diffing against widgets built with the old colors.
    AppColors.configure(appearance);
    return MaterialApp.router(
      key: ValueKey(appearance),
      title: 'Shaddai Reader',
      theme: buildAppTheme(appearance),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          ConnectivityBanner(child: child ?? const SizedBox.shrink()),
    );
  }
}
