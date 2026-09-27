import 'dart:async';
import 'dart:io';

import '../../backends/local/local_importer.dart';
import '../../backends/local/local_library_store.dart';
import 'watch_folder_store.dart';

const _archiveExtensions = ['.cbz', '.zip'];

/// Watches a chosen folder (while the app is running - there's no true
/// background service here) and auto-imports anything new dropped into it:
/// a loose CBZ/ZIP file becomes one chapter, a subfolder of images becomes
/// one chapter via [importFolder]. Already-imported entries are tracked by
/// path in [WatchFolderStore] so a restart or a re-scan doesn't redo them.
class WatchFolderService {
  final LocalLibraryStore libraryStore;
  final WatchFolderStore watchStore;
  final void Function() onImported;

  StreamSubscription<FileSystemEvent>? _sub;

  WatchFolderService({
    required this.libraryStore,
    required this.watchStore,
    required this.onImported,
  });

  bool get isWatching => _sub != null;

  Future<void> start() async {
    await stop();
    final path = watchStore.path;
    if (path == null) return;
    final dir = Directory(path);
    if (!await dir.exists()) return;

    await _scanExisting(dir);
    _sub = dir.watch().listen((event) {
      if (event.type == FileSystemEvent.create ||
          event.type == FileSystemEvent.move) {
        _handleEntry(event.path);
      }
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> _scanExisting(Directory dir) async {
    await for (final entity in dir.list()) {
      await _handleEntry(entity.path);
    }
  }

  Future<void> _handleEntry(String entryPath) async {
    if (watchStore.hasSeen(entryPath)) return;
    // A file/folder mid-copy isn't ready yet - give it a moment before
    // trying, and just skip it for now on any failure (the next start()
    // or filesystem event will retry, since it's still unmarked).
    await Future.delayed(const Duration(seconds: 2));
    try {
      final type = await FileSystemEntity.type(entryPath);
      if (type == FileSystemEntityType.file) {
        final lower = entryPath.toLowerCase();
        if (!_archiveExtensions.any(lower.endsWith)) return;
        final name = entryPath
            .split(RegExp(r'[/\\]'))
            .where((s) => s.isNotEmpty)
            .last;
        final bytes = await File(entryPath).readAsBytes();
        await importArchive(store: libraryStore, fileName: name, bytes: bytes);
      } else if (type == FileSystemEntityType.directory) {
        await importFolder(store: libraryStore, folderPath: entryPath);
      } else {
        return;
      }
      await watchStore.markSeen(entryPath);
      onImported();
    } on ImportException {
      // Not a comic (e.g. a stray file) - mark seen so it's not retried forever.
      await watchStore.markSeen(entryPath);
    } catch (_) {
      // Transient (still copying, permission blip) - leave unmarked to retry.
    }
  }
}
