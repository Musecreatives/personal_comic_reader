import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backends/kavita/kavita_backend.dart';
import '../backends/komga/komga_backend.dart';
import '../backends/opds/opds_backend.dart';
import '../backends/suwayomi/suwayomi_backend.dart';
import '../core/appearance/appearance_settings.dart';
import '../core/appearance/appearance_store.dart';
import '../core/backend/reader_backend.dart';
import '../core/collections/collections_store.dart';
import '../core/history/history_store.dart';
import '../core/downloads/download_manager.dart';
import '../core/downloads/download_models.dart';
import '../core/downloads/download_store.dart';
import '../core/kapowarr/kapowarr_config.dart';
import '../core/kapowarr/kapowarr_config_store.dart';
import '../core/reader/page_cache.dart';
import '../core/reader/progress_sync.dart';
import '../core/reader/reader_settings_store.dart';
import '../core/stats/reading_stats_store.dart';
import '../core/storage/server_store.dart';
import '../core/sync/auth_store.dart';
import '../core/sync/sync_client.dart';
import '../core/sync/sync_queue.dart';

/// Set once in main() after ServerStore.init() completes.
final serverStoreProvider = Provider<ServerStore>((ref) {
  throw UnimplementedError('serverStoreProvider must be overridden in main()');
});

/// List of configured servers. Bump [serverListRevisionProvider] after any
/// add/edit/delete so screens watching this refetch.
final serverListRevisionProvider = StateProvider<int>((ref) => 0);

final serverListProvider = Provider<List<ServerConfig>>((ref) {
  ref.watch(serverListRevisionProvider);
  return ref.watch(serverStoreProvider).listServers();
});

final activeServerIdProvider = StateProvider<String?>((ref) {
  return ref.watch(serverStoreProvider).getActiveServerId();
});

final activeServerConfigProvider = Provider<ServerConfig?>((ref) {
  final id = ref.watch(activeServerIdProvider);
  if (id == null) return null;
  ref.watch(serverListRevisionProvider);
  return ref.watch(serverStoreProvider).getServer(id);
});

/// Builds the right [ReaderBackend] implementation for [config]. UI code
/// should never call this directly - go through [activeBackendProvider] or
/// [allBackendsProvider] instead.
ReaderBackend buildBackend(ServerConfig config, String password) {
  switch (config.type) {
    case ServerType.komga:
      return KomgaBackend(config: config, password: password);
    case ServerType.kavita:
      return KavitaBackend(config: config, password: password);
    case ServerType.suwayomi:
      return SuwayomiBackend(config: config, password: password);
    case ServerType.opds:
      return OpdsBackend(config: config, password: password);
  }
}

/// The live backend instance for whichever server is active. UI code
/// should only ever go through this - never construct a backend directly.
final activeBackendProvider = FutureProvider<ReaderBackend?>((ref) async {
  final config = ref.watch(activeServerConfigProvider);
  if (config == null) return null;

  final store = ref.watch(serverStoreProvider);
  final password = await store.getPassword(config.id) ?? '';
  return buildBackend(config, password);
});

/// One backend per configured server (not just the active one) - used by
/// cross-server search (5c), which needs to query every server at once.
final allBackendsProvider = FutureProvider<List<ReaderBackend>>((ref) async {
  final servers = ref.watch(serverListProvider);
  final store = ref.watch(serverStoreProvider);
  return Future.wait(servers.map((config) async {
    final password = await store.getPassword(config.id) ?? '';
    return buildBackend(config, password);
  }));
});

/// Set once in main() after ReaderSettingsStore.init() completes.
final readerSettingsStoreProvider = Provider<ReaderSettingsStore>((ref) {
  throw UnimplementedError(
      'readerSettingsStoreProvider must be overridden in main()');
});

/// Set once in main() after ProgressSync.init() completes. Lives for the
/// whole app so its debounce timer and offline queue survive navigating
/// away from and back into the reader.
final progressSyncProvider = Provider<ProgressSync>((ref) {
  throw UnimplementedError('progressSyncProvider must be overridden in main()');
});

/// Set once in main() after PageCache.init() completes.
final pageCacheProvider = Provider<PageCache>((ref) {
  throw UnimplementedError('pageCacheProvider must be overridden in main()');
});

/// Set once in main() after KapowarrConfigStore.init() completes.
final kapowarrConfigStoreProvider = Provider<KapowarrConfigStore>((ref) {
  throw UnimplementedError(
      'kapowarrConfigStoreProvider must be overridden in main()');
});

/// Bump after saving/clearing the Kapowarr config so watchers refetch.
final kapowarrConfigRevisionProvider = StateProvider<int>((ref) => 0);

final kapowarrConfigProvider = FutureProvider<KapowarrConfig?>((ref) {
  ref.watch(kapowarrConfigRevisionProvider);
  return ref.watch(kapowarrConfigStoreProvider).getWithApiKey();
});

/// Set once in main() after DownloadStore.init() completes.
final downloadStoreProvider = Provider<DownloadStore>((ref) {
  throw UnimplementedError('downloadStoreProvider must be overridden in main()');
});

/// Set once in main() - lives for the whole app so downloads keep running
/// across navigation.
final downloadManagerProvider = Provider<DownloadManager>((ref) {
  throw UnimplementedError('downloadManagerProvider must be overridden in main()');
});

/// The live download queue, re-emitted every time [DownloadManager] reports
/// a change (progress tick, state change, enqueue, cancel...).
final downloadQueueProvider = StreamProvider<List<DownloadTask>>((ref) async* {
  final manager = ref.watch(downloadManagerProvider);
  final store = ref.watch(downloadStoreProvider);
  yield store.listTasks();
  await for (final _ in manager.changes) {
    yield store.listTasks();
  }
});

/// Set once in main() after ReadingStatsStore.init() completes.
final readingStatsStoreProvider = Provider<ReadingStatsStore>((ref) {
  throw UnimplementedError(
      'readingStatsStoreProvider must be overridden in main()');
});

/// Set once in main() after AppearanceStore.init() completes.
final appearanceStoreProvider = Provider<AppearanceStore>((ref) {
  throw UnimplementedError('appearanceStoreProvider must be overridden in main()');
});

/// Live appearance state - seeded from the store at startup in main(), then
/// updated in place (and persisted) by the Appearance screen. MaterialApp
/// watches this to rebuild the theme immediately on change.
final appearanceProvider = StateProvider<AppearanceSettings>((ref) {
  throw UnimplementedError('appearanceProvider must be overridden in main()');
});

/// Set once in main() after HistoryStore.init() completes.
final historyStoreProvider = Provider<HistoryStore>((ref) {
  throw UnimplementedError('historyStoreProvider must be overridden in main()');
});

/// Bump after any history record/clear so screens watching this refetch -
/// the store itself doesn't notify, mirroring [collectionsRevisionProvider].
final historyRevisionProvider = StateProvider<int>((ref) => 0);

/// Set once in main() after CollectionsStore.init() completes.
final collectionsStoreProvider = Provider<CollectionsStore>((ref) {
  throw UnimplementedError('collectionsStoreProvider must be overridden in main()');
});

/// Bump after any collection create/delete/add-series/remove-series so
/// screens watching this refetch.
final collectionsRevisionProvider = StateProvider<int>((ref) => 0);

/// Set once in main() - wraps secure-storage access to the signed-in
/// shaddai-sync session (bearer token + username).
final authStoreProvider = Provider<AuthStore>((ref) {
  throw UnimplementedError('authStoreProvider must be overridden in main()');
});

/// Set once in main() after SyncQueue.init() completes.
final syncQueueProvider = Provider<SyncQueue>((ref) {
  throw UnimplementedError('syncQueueProvider must be overridden in main()');
});

/// Set once in main() - a single long-lived [SyncClient], constructed with
/// whatever session token was found in secure storage at startup (or none).
/// The login screen calls `.updateToken(...)` on it directly after a
/// successful login/logout rather than rebuilding a new client, since it
/// has no other per-request state worth discarding.
final syncClientProvider = Provider<SyncClient>((ref) {
  throw UnimplementedError('syncClientProvider must be overridden in main()');
});

/// The signed-in username, or null if no session exists - seeded from
/// [AuthStore] at startup in main(), same pattern as [appearanceProvider].
/// The router's auth gate watches this: null routes to /login.
final currentUsernameProvider = StateProvider<String?>((ref) {
  throw UnimplementedError('currentUsernameProvider must be overridden in main()');
});
