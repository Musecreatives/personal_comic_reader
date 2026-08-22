import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backends/kavita/kavita_backend.dart';
import '../backends/komga/komga_backend.dart';
import '../core/backend/reader_backend.dart';
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
  }
});
