import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backends/komga/komga_backend.dart';
import '../backends/local/local_backend.dart';
import '../backends/local/local_library_store.dart';
import '../backends/opds/opds_backend.dart';
import '../backends/suwayomi/suwayomi_backend.dart';
import '../core/appearance/appearance_settings.dart';
import '../core/appearance/appearance_store.dart';
import '../core/backend/reader_backend.dart';
import '../core/collections/collections_store.dart';
import '../core/history/history_entry.dart';
import '../core/history/history_store.dart';
import '../core/history/stopped_series_store.dart';
import '../core/downloads/download_manager.dart';
import '../core/downloads/download_models.dart';
import '../core/downloads/download_store.dart';
import '../core/kapowarr/kapowarr_config.dart';
import '../core/kapowarr/kapowarr_config_store.dart';
import '../core/media_pool/media_pool_config_store.dart';
import '../core/local_watch/watch_folder_service.dart';
import '../core/local_watch/watch_folder_store.dart';
import '../core/notifications/chapter_watch_store.dart';
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

/// The always-present pseudo-server for manually-imported comics/manga -
/// never added or removed through Settings, just prepended to whatever the
/// user has actually configured.
const localLibraryServerConfig = ServerConfig(
  id: 'local',
  name: 'On This Device',
  type: ServerType.local,
  baseUrl: '',
  username: '',
);

final serverListProvider = Provider<List<ServerConfig>>((ref) {
  ref.watch(serverListRevisionProvider);
  return [localLibraryServerConfig, ...ref.watch(serverStoreProvider).listServers()];
});

final activeServerIdProvider = StateProvider<String?>((ref) {
  return ref.watch(serverStoreProvider).getActiveServerId();
});

final activeServerConfigProvider = Provider<ServerConfig?>((ref) {
  final id = ref.watch(activeServerIdProvider);
  if (id == null) return null;
  // serverListProvider (not serverStoreProvider.getServer) since it's the
  // one that also knows about the local pseudo-server.
  return ref.watch(serverListProvider).where((s) => s.id == id).firstOrNull;
});

/// Set once in main() after LocalLibraryStore.init() completes.
final localLibraryStoreProvider = Provider<LocalLibraryStore>((ref) {
  throw UnimplementedError(
      'localLibraryStoreProvider must be overridden in main()');
});

/// Set once in main() after WatchFolderStore.init() completes.
final watchFolderStoreProvider = Provider<WatchFolderStore>((ref) {
  throw UnimplementedError(
      'watchFolderStoreProvider must be overridden in main()');
});

/// Set once in main(), after the ProviderContainer exists (its onImported
/// callback needs to read back into that same container).
final watchFolderServiceProvider = Provider<WatchFolderService>((ref) {
  throw UnimplementedError(
      'watchFolderServiceProvider must be overridden in main()');
});

/// Set once in main() after ChapterWatchStore.init() completes.
final chapterWatchStoreProvider = Provider<ChapterWatchStore>((ref) {
  throw UnimplementedError(
      'chapterWatchStoreProvider must be overridden in main()');
});

/// Builds the right [ReaderBackend] implementation for [config]. UI code
/// should never call this directly - go through [activeBackendProvider] or
/// [allBackendsProvider] instead.
ReaderBackend buildBackend(
  ServerConfig config,
  String password, {
  required LocalLibraryStore localStore,
}) {
  switch (config.type) {
    case ServerType.komga:
      return KomgaBackend(config: config, password: password);
    case ServerType.suwayomi:
      return SuwayomiBackend(config: config, password: password);
    case ServerType.opds:
      return OpdsBackend(config: config, password: password);
    case ServerType.local:
      return LocalBackend(config: config, store: localStore);
  }
}

/// The live backend instance for whichever server is active. UI code
/// should only ever go through this - never construct a backend directly.
final activeBackendProvider = FutureProvider<ReaderBackend?>((ref) async {
  final config = ref.watch(activeServerConfigProvider);
  if (config == null) return null;

  final store = ref.watch(serverStoreProvider);
  final localStore = ref.watch(localLibraryStoreProvider);
  final password = await store.getPassword(config.id) ?? '';
  return buildBackend(config, password, localStore: localStore);
});

/// One backend per configured server (not just the active one) - used by
/// cross-server search (5c), which needs to query every server at once.
final allBackendsProvider = FutureProvider<List<ReaderBackend>>((ref) async {
  final servers = ref.watch(serverListProvider);
  final store = ref.watch(serverStoreProvider);
  final localStore = ref.watch(localLibraryStoreProvider);
  return Future.wait(servers.map((config) async {
    final password = await store.getPassword(config.id) ?? '';
    return buildBackend(config, password, localStore: localStore);
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

/// Set once in main() after MediaPoolConfigStore.init() completes.
final mediaPoolConfigStoreProvider = Provider<MediaPoolConfigStore>((ref) {
  throw UnimplementedError(
      'mediaPoolConfigStoreProvider must be overridden in main()');
});

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

/// What's been read across *every* server, newest first - Home merges all
/// sources, so "continue" means the last thing read anywhere. Entries
/// recorded before servers were tracked (`serverId == null`) belong to
/// whichever server is active. This drives Home's hero and the persistent
/// now-reading bar: a server only knows which chapters are unread, not which
/// one was read *last*.
final recentReadingProvider = Provider<List<HistoryEntry>>((ref) {
  ref.watch(historyRevisionProvider);
  ref.watch(stoppedRevisionProvider);
  final activeId = ref.watch(activeServerIdProvider);
  final stopped = ref.watch(stoppedSeriesStoreProvider);
  return ref
      .watch(historyStoreProvider)
      .list()
      // A series the user stopped stays hidden until they read it again.
      .where((e) => !stopped.isStopped('${e.serverId ?? activeId}|${e.seriesId}',
          lastReadAt: e.timestamp))
      .toList();
});

/// Set once in main() after StoppedSeriesStore.init() completes.
final stoppedSeriesStoreProvider = Provider<StoppedSeriesStore>((ref) {
  throw UnimplementedError(
      'stoppedSeriesStoreProvider must be overridden in main()');
});

/// Bump after stopping or resuming a series so Home refilters.
final stoppedRevisionProvider = StateProvider<int>((ref) => 0);

/// The backend for [serverId] (or the active one when null, i.e. a legacy
/// history entry from before servers were tracked). Null if that server has
/// since been removed.
final backendForServerProvider =
    FutureProvider.family<ReaderBackend?, String?>((ref, serverId) async {
  if (serverId == null) return ref.watch(activeBackendProvider.future);
  final all = await ref.watch(allBackendsProvider.future);
  return all.where((b) => b.config.id == serverId).firstOrNull;
});

/// Makes [serverId] the active server (if it still exists) so screens that
/// read [activeBackendProvider] - series, reader - talk to the right one
/// after tapping something that lives on another server.
Future<void> activateServer(WidgetRef ref, String? serverId) async {
  if (serverId == null || serverId == ref.read(activeServerIdProvider)) return;
  final store = ref.read(serverStoreProvider);
  if (store.getServer(serverId) == null) return;
  await store.setActiveServerId(serverId);
  ref.read(activeServerIdProvider.notifier).state = serverId;
}

/// Timestamp of the history entry whose now-reading bar was dismissed.
/// Reading again writes a newer timestamp, which brings the bar back.
final nowReadingDismissedProvider = StateProvider<DateTime?>((ref) => null);

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

/// Attaches every synced store (history, collections, appearance, reader
/// settings) to the current session and pulls remote changes, refreshing the
/// UI providers for whatever changed. Called at startup and after login;
/// each store is best-effort so one failure never blocks the rest.
Future<void> startSync(ProviderContainer c, {bool force = true}) async {
  final status = c.read(syncStatusProvider.notifier);
  final current = status.state;
  if (current.phase == SyncPhase.syncing) return;
  // Callers that fire often (app resume, the periodic timer) pass
  // force: false so a recent successful sync is not repeated.
  final last = current.lastOk;
  if (!force &&
      last != null &&
      DateTime.now().difference(last) < const Duration(seconds: 45)) {
    return;
  }
  status.state = SyncStatus(phase: SyncPhase.syncing, lastOk: last);

  final client = c.read(syncClientProvider);
  final queue = c.read(syncQueueProvider);
  final servers = c.read(serverStoreProvider);
  final history = c.read(historyStoreProvider)..attachSync(client, queue);
  final collections = c.read(collectionsStoreProvider)
    ..sync.attach(client, queue);
  final appearance = c.read(appearanceStoreProvider)..sync.attach(client, queue);
  final reader = c.read(readerSettingsStoreProvider)..sync.attach(client, queue);
  final stats = c.read(readingStatsStoreProvider)..sync.attach(client, queue);

  // A history entry names the server by the id it had on the device that
  // read it; map that to this device's id for the same server.
  String? resolveServer(String? id, String? key) {
    final all = servers.listServers();
    if (id != null && all.any((s) => s.id == id)) return id;
    if (key == null) return null;
    return all.where((s) => s.portableKey == key).firstOrNull?.id;
  }

  var failed = false;
  Future<void> run(Future<bool> Function() reconcile, void Function() onChanged) async {
    try {
      if (await reconcile()) onChanged();
    } catch (_) {
      // Offline or server down: stay on local data until the next attempt.
      failed = true;
    }
  }

  await Future.wait([
    run(() async {
      await history.reconcile(resolveServer: resolveServer);
      return true;
    }, () => c.read(historyRevisionProvider.notifier).state++),
    run(collections.reconcile,
        () => c.read(collectionsRevisionProvider.notifier).state++),
    run(appearance.reconcile,
        () => c.read(appearanceProvider.notifier).state = appearance.get()),
    run(reader.reconcile, () {}),
    run(stats.reconcile, () => c.read(statsRevisionProvider.notifier).state++),
  ]);
  status.state = failed
      ? SyncStatus(phase: SyncPhase.offline, lastOk: last)
      : SyncStatus(phase: SyncPhase.idle, lastOk: DateTime.now());
}

/// Restarts downloads that were queued or in flight when the app last closed.
Future<void> resumeDownloads(ProviderContainer c) async {
  try {
    final backends = await c.read(allBackendsProvider.future);
    await c
        .read(downloadManagerProvider)
        .resumePending({for (final b in backends) b.config.id: b});
  } catch (_) {
    // Best-effort; the Downloads screen can still resume a task by hand.
  }
}

enum SyncPhase { idle, syncing, offline }

/// What the settings screen shows: whether a sync is running, failed, and
/// when the last good one finished.
class SyncStatus {
  final SyncPhase phase;
  final DateTime? lastOk;
  const SyncStatus({this.phase = SyncPhase.idle, this.lastOk});
}

final syncStatusProvider = StateProvider<SyncStatus>((ref) => const SyncStatus());

/// Bumped when synced stats change so the Stats screen refetches.
final statsRevisionProvider = StateProvider<int>((ref) => 0);

/// The signed-in username, or null if no session exists - seeded from
/// [AuthStore] at startup in main(), same pattern as [appearanceProvider].
/// The router's auth gate watches this: null routes to /login.
final currentUsernameProvider = StateProvider<String?>((ref) {
  throw UnimplementedError('currentUsernameProvider must be overridden in main()');
});
