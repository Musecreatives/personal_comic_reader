import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'app/chapter_notification_scheduler.dart';
import 'app/connectivity_banner.dart';
import 'app/design_tokens.dart';
import 'app/providers.dart';
import 'app/router.dart';
import 'app/sync_scheduler.dart';
import 'app/theme.dart';
import 'backends/local/local_library_store.dart';
import 'core/appearance/appearance_store.dart';
import 'core/collections/collections_store.dart';
import 'core/downloads/download_manager.dart';
import 'core/history/history_store.dart';
import 'core/history/stopped_series_store.dart';
import 'core/downloads/download_store.dart';
import 'core/kapowarr/kapowarr_config_store.dart';
import 'core/local_watch/watch_folder_service.dart';
import 'core/local_watch/watch_folder_store.dart';
import 'core/media_pool/media_pool_config_store.dart';
import 'core/notifications/chapter_watch_store.dart';
import 'core/reader/page_cache.dart';
import 'core/reader/progress_sync.dart';
import 'core/reader/reader_settings_store.dart';
import 'core/stats/reading_stats_store.dart';
import 'core/storage/last_route_store.dart';
import 'core/storage/server_store.dart';
import 'core/sync/auth_store.dart';
import 'core/sync/sync_client.dart';
import 'core/sync/sync_queue.dart';
import 'features/local_library/local_library_screen.dart' show localLibraryRevisionProvider;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Directory? supportDir;
  if (kIsWeb) {
    // path_provider has no web implementation; Hive uses IndexedDB on web
    // regardless of the path passed in, so the default is fine there.
    await Hive.initFlutter();
  } else {
    // Use the OS app-data directory (not the user's visible Documents
    // folder, which on Windows is usually OneDrive-synced) so box files
    // don't clutter it or get cloud-synced as loose, meaningless filenames.
    supportDir = await getApplicationSupportDirectory();
    Hive.init(supportDir.path);
  }

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

  final mediaPoolConfigStore = MediaPoolConfigStore();
  await mediaPoolConfigStore.init();

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

  final stoppedSeriesStore = StoppedSeriesStore();
  await stoppedSeriesStore.init();

  final localLibraryStore = LocalLibraryStore(
    pagesDir: supportDir == null
        ? null
        : Directory('${supportDir.path}${Platform.pathSeparator}local_library_pages'),
  );
  await localLibraryStore.init();

  final watchFolderStore = WatchFolderStore();
  await watchFolderStore.init();

  final chapterWatchStore = ChapterWatchStore();
  await chapterWatchStore.init();
  await setUpChapterNotifications();

  final authStore = AuthStore();
  final syncToken = await authStore.getToken();
  final syncUsername = await authStore.getUsername();

  final syncQueue = SyncQueue();
  await syncQueue.init();

  final syncClient =
      SyncClient(baseUrl: SyncClient.defaultBaseUrl(), token: syncToken);

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

  // `container` isn't assigned until below, but this closure is only ever
  // called later (on a filesystem event), by which point it will be - a
  // plain forward reference, not a use-before-assignment.
  late final ProviderContainer container;
  final watchFolderService = WatchFolderService(
    libraryStore: localLibraryStore,
    watchStore: watchFolderStore,
    onImported: () =>
        container.read(localLibraryRevisionProvider.notifier).state++,
  );

  container = ProviderContainer(
      overrides: [
        serverStoreProvider.overrideWithValue(serverStore),
        readerSettingsStoreProvider.overrideWithValue(readerSettingsStore),
        progressSyncProvider.overrideWithValue(progressSync),
        pageCacheProvider.overrideWithValue(pageCache),
        kapowarrConfigStoreProvider.overrideWithValue(kapowarrConfigStore),
        mediaPoolConfigStoreProvider.overrideWithValue(mediaPoolConfigStore),
        downloadStoreProvider.overrideWithValue(downloadStore),
        downloadManagerProvider.overrideWithValue(downloadManager),
        readingStatsStoreProvider.overrideWithValue(readingStatsStore),
        appearanceStoreProvider.overrideWithValue(appearanceStore),
        appearanceProvider.overrideWith((ref) => initialAppearance),
        historyStoreProvider.overrideWithValue(historyStore),
        collectionsStoreProvider.overrideWithValue(collectionsStore),
        stoppedSeriesStoreProvider.overrideWithValue(stoppedSeriesStore),
        localLibraryStoreProvider.overrideWithValue(localLibraryStore),
        watchFolderStoreProvider.overrideWithValue(watchFolderStore),
        watchFolderServiceProvider.overrideWithValue(watchFolderService),
        chapterWatchStoreProvider.overrideWithValue(chapterWatchStore),
        authStoreProvider.overrideWithValue(authStore),
        syncQueueProvider.overrideWithValue(syncQueue),
        syncClientProvider.overrideWithValue(syncClient),
        currentUsernameProvider.overrideWith((ref) => syncUsername),
      ],
  );

  // Best-effort - don't block startup on a network round trip. Failures
  // just mean this device stays on what it already has locally until
  // the next successful sync (e.g. next app launch).
  if (syncToken != null) unawaited(startSync(container));
  unawaited(resumeDownloads(container));
  unawaited(watchFolderService.start());

  runApp(UncontrolledProviderScope(
    container: container,
    child: ShaddaiReaderApp(router: router),
  ));
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
      builder: (context, child) => SyncScheduler(
        child: ChapterNotificationScheduler(
          child: ConnectivityBanner(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
