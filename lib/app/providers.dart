import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backends/kavita/kavita_backend.dart';
import '../backends/komga/komga_backend.dart';
import '../backends/suwayomi/suwayomi_backend.dart';
import '../core/backend/reader_backend.dart';
import '../core/downloads/download_manager.dart';
import '../core/downloads/download_models.dart';
import '../core/downloads/download_store.dart';
import '../core/kapowarr/kapowarr_config.dart';
import '../core/kapowarr/kapowarr_config_store.dart';
import '../core/reader/page_cache.dart';
import '../core/reader/progress_sync.dart';
import '../core/reader/reader_settings_store.dart';
import '../core/storage/server_store.dart';

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

/// The live backend instance for whichever server is active. UI code
/// should only ever go through this - never construct a backend directly.
final activeBackendProvider = FutureProvider<ReaderBackend?>((ref) async {
  final config = ref.watch(activeServerConfigProvider);
  if (config == null) return null;

  final store = ref.watch(serverStoreProvider);
  final password = await store.getPassword(config.id) ?? '';

  switch (config.type) {
    case ServerType.komga:
      return KomgaBackend(config: config, password: password);
    case ServerType.kavita:
      return KavitaBackend(config: config, password: password);
    case ServerType.suwayomi:
      return SuwayomiBackend(config: config, password: password);
  }
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
