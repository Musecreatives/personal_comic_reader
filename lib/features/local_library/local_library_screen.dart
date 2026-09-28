import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../backends/local/local_importer.dart';
import '../../backends/local/local_library_store.dart';
import '../../core/media_pool/webdav_client.dart';
import '../shared/back_button.dart';
import '../shared/series_cover.dart';

/// Bumped after every import/delete so the screen (and Home/Search, which
/// also read through [LocalLibraryStore] via [LocalBackend]) refetch.
final localLibraryRevisionProvider = StateProvider<int>((ref) => 0);

/// Manually-imported comics/manga (CBZ/ZIP archives) - "On This Device" in
/// the server switcher. Reading, progress, and history all go through the
/// same [LocalBackend] path every other server uses; this screen only adds
/// the import button and the local-only delete action.
class LocalLibraryScreen extends ConsumerStatefulWidget {
  const LocalLibraryScreen({super.key});

  @override
  ConsumerState<LocalLibraryScreen> createState() => _LocalLibraryScreenState();
}

class _LocalLibraryScreenState extends ConsumerState<LocalLibraryScreen> {
  bool _importing = false;

  String? get _watchedFolder =>
      kIsWeb ? null : ref.read(watchFolderStoreProvider).path;

  Future<void> _chooseWatchFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    await ref.read(watchFolderStoreProvider).setPath(path);
    await ref.read(watchFolderServiceProvider).start();
    if (mounted) setState(() {});
  }

  Future<void> _stopWatching() async {
    await ref.read(watchFolderServiceProvider).stop();
    await ref.read(watchFolderStoreProvider).setPath(null);
    if (mounted) setState(() {});
  }

  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: importableArchiveExtensions,
        allowMultiple: true,
      );
      if (files.isEmpty) return;

      final store = ref.read(localLibraryStoreProvider);
      var ok = 0;
      final errors = <String>[];
      for (final f in files) {
        try {
          final path = f.path;
          if (path != null) {
            // Straight from disk: handles RAR/7z too, and never loads the
            // whole archive into memory.
            await importArchiveFile(store: store, path: path);
          } else {
            await importArchive(
                store: store, fileName: f.name, bytes: await f.readAsBytes());
          }
          ok++;
        } on ImportException catch (e) {
          errors.add('${f.name}: $e');
        } catch (e) {
          errors.add('${f.name}: Import failed ($e)');
        }
      }

      ref.read(localLibraryRevisionProvider.notifier).state++;
      if (!mounted) return;
      final message = errors.isEmpty
          ? 'Imported $ok chapter${ok == 1 ? '' : 's'}'
          : '$ok imported, ${errors.length} failed: ${errors.first}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't import: $e")),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importFolder() async {
    setState(() => _importing = true);
    try {
      final path = await FilePicker.getDirectoryPath();
      if (path == null) return;

      final store = ref.read(localLibraryStoreProvider);
      await importFolder(store: store, folderPath: path);

      ref.read(localLibraryRevisionProvider.notifier).state++;
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Imported 1 chapter')));
    } on ImportException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Couldn't import: $e")));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importLooseImages() async {
    setState(() => _importing = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      if (files.isEmpty) return;

      final picked = await Future.wait(files.map(
          (f) async => PickedImageFile(f.name, await f.readAsBytes())));
      final store = ref.read(localLibraryStoreProvider);
      await importLooseFiles(
        store: store,
        files: picked,
        chapterTitle: 'Imported pages',
      );

      ref.read(localLibraryRevisionProvider.notifier).state++;
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Imported 1 chapter')));
    } on ImportException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Couldn't import: $e")));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _openSeries(String seriesId) async {
    await activateServer(ref, 'local');
    if (!mounted) return;
    context.push('/series/${Uri.encodeComponent(seriesId)}');
  }

  Future<void> _renameSeries(LocalSeriesRecord series) async {
    final controller = TextEditingController(text: series.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppText.body(size: 14),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newTitle == null || newTitle.isEmpty || newTitle == series.title) return;
    final store = ref.read(localLibraryStoreProvider);
    await store.putSeries(LocalSeriesRecord(
      id: series.id,
      title: newTitle,
      addedAt: series.addedAt,
    ));
    ref.read(localLibraryRevisionProvider.notifier).state++;
  }

  Future<void> _exportSeries(LocalSeriesRecord series) async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    final store = ref.read(localLibraryStoreProvider);
    try {
      final count = await exportSeriesToFolder(
        store: store,
        seriesId: series.id,
        folderPath: path,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported $count chapter${count == 1 ? '' : 's'}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Couldn't export: $e")));
    }
  }

  /// Which top-level media-pool folder a series' upload goes into. Asked
  /// once per series (there's no reliable way to guess from the file) and
  /// remembered on the record so re-uploads (new chapters) don't ask again.
  Future<String?> _askContentKind(String seriesTitle) {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Comic or manga/manhwa?'),
        content: Text('"$seriesTitle" - which media pool folder should this go in?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, 'comic'),
              child: const Text('Comic')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'manga'),
              child: const Text('Manga/Manhwa')),
        ],
      ),
    );
  }

  Future<void> _uploadSeries(LocalSeriesRecord series) async {
    final config = await ref.read(mediaPoolConfigStoreProvider).getWithPassword();
    if (config == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Set up the media pool in Settings first'),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: () => context.push('/settings/media-pool'),
        ),
      ));
      return;
    }
    final store = ref.read(localLibraryStoreProvider);
    var kind = series.contentKind;
    if (kind == null) {
      kind = await _askContentKind(series.title);
      if (kind == null) return; // dismissed
      await store.putSeries(series.copyWith(contentKind: kind));
    }
    final folder = kind == 'comic' ? 'Comics' : 'Manga';

    final books = store.listBooksForSeries(series.id);
    final client = WebDavClient(config: config);
    var ok = 0;
    final errors = <String>[];
    for (final book in books) {
      final remote =
          '$folder/${sanitizeFileName(series.title)}/${sanitizeFileName(book.title)}.cbz';
      try {
        if (kIsWeb) {
          await client.putFile(remote, await exportBookToCbz(store, book));
        } else {
          // Build the CBZ on disk and stream it up - a big book never has to
          // fit in memory.
          final temp = await Directory.systemTemp.createTemp('shaddai_upload_');
          try {
            final cbz = File('${temp.path}${Platform.pathSeparator}book.cbz');
            await exportBookToCbzFile(store, book, cbz.path);
            await client.putFileFromDisk(remote, cbz);
          } finally {
            await temp.delete(recursive: true);
          }
        }
        ok++;
      } catch (e) {
        errors.add('${book.title}: $e');
      }
    }
    if (!mounted) return;
    final message = errors.isEmpty
        ? 'Uploaded $ok chapter${ok == 1 ? '' : 's'} to $folder'
        : '$ok uploaded, ${errors.length} failed: ${errors.first}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  void _showSeriesActions(LocalSeriesRecord series) {
    showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: Motion.sheetStyle,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.text30,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(series.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.heading(size: 18)),
            ),
            _SeriesAction(
              icon: Icons.edit_outlined,
              title: 'Rename',
              onTap: () {
                Navigator.pop(sheetContext);
                _renameSeries(series);
              },
            ),
            _SeriesAction(
              icon: Icons.folder_open_outlined,
              title: 'Export to folder',
              hint: 'Saves every chapter here as a CBZ file',
              onTap: () {
                Navigator.pop(sheetContext);
                _exportSeries(series);
              },
            ),
            _SeriesAction(
              icon: Icons.cloud_upload_outlined,
              title: 'Upload to media pool',
              hint: 'Backs it up to your configured WebDAV folder',
              onTap: () {
                Navigator.pop(sheetContext);
                _uploadSeries(series);
              },
            ),
            _SeriesAction(
              icon: Icons.delete_outline_rounded,
              title: 'Delete',
              destructive: true,
              onTap: () {
                Navigator.pop(sheetContext);
                _deleteSeries(series);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSeries(LocalSeriesRecord series) async {
    final store = ref.read(localLibraryStoreProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Delete this import?'),
        content: Text(
            '"${series.title}" and everything imported under it will be removed from this device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final b in store.listBooksForSeries(series.id)) {
      await store.deleteBook(b.id);
    }
    ref.read(localLibraryRevisionProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localLibraryRevisionProvider);
    final store = ref.watch(localLibraryStoreProvider);
    final series = store.listSeries();

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppScreenHeader(
              title: 'On This Device',
              trailing: _ImportMenuButton(
                importing: _importing,
                onImportArchive: _import,
                onImportFolder: kIsWeb ? null : _importFolder,
                onImportLooseImages: _importLooseImages,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                canUnpackNonZipArchives
                    ? 'CBZ, CBR, CB7 and ZIP/RAR/7z archives, whole folders of '
                        'page images, or loose image files.'
                    : 'CBZ/ZIP archives, or loose image files. RAR-based CBR '
                        'files can be imported from the desktop app.',
                style: AppText.body(size: 12, color: AppColors.text45),
              ),
            ),
            if (!kIsWeb)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: _WatchFolderRow(
                  path: _watchedFolder,
                  onChoose: _chooseWatchFolder,
                  onStop: _stopWatching,
                ),
              ),
            Expanded(
              child: series.isEmpty
                  ? _EmptyState(importing: _importing, onImport: _import)
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.62,
                      ),
                      itemCount: series.length,
                      itemBuilder: (context, i) {
                        final s = series[i];
                        final books = store.listBooksForSeries(s.id);
                        final coverBook = books.isEmpty ? null : books.last;
                        return FadeSlideIn(
                          delay: Duration(milliseconds: 30 * (i % 12)),
                          child: GestureDetector(
                            onTap: () => _openSeries(s.id),
                            onLongPress: () => _showSeriesActions(s),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: coverBook == null
                                        ? const SeriesCover(imageUrl: null)
                                        : LocalPageThumbnail(
                                            store: store, bookId: coverBook.id),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  s.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.body(size: 12.5, weight: FontWeight.w600),
                                ),
                                Text(
                                  '${books.length} CH',
                                  style: AppText.mono(size: 9.5),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportMenuButton extends StatelessWidget {
  final bool importing;
  final VoidCallback onImportArchive;
  final VoidCallback? onImportFolder;
  final VoidCallback onImportLooseImages;

  const _ImportMenuButton({
    required this.importing,
    required this.onImportArchive,
    required this.onImportFolder,
    required this.onImportLooseImages,
  });

  @override
  Widget build(BuildContext context) {
    if (importing) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return PopupMenuButton<VoidCallback>(
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: onImportArchive,
          child: const Text('Comic archive (CBZ/ZIP)'),
        ),
        PopupMenuItem(
          value: onImportFolder,
          enabled: onImportFolder != null,
          child: Text(onImportFolder == null
              ? 'Folder of images (not on web)'
              : 'Folder of images'),
        ),
        PopupMenuItem(
          value: onImportLooseImages,
          child: const Text('Loose image files'),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 18, color: Colors.white),
            SizedBox(width: 6),
            Text('Import', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// First page of a locally-imported book as a cover. On desktop/mobile it's
/// decoded straight from the page file at thumbnail size (an omnibus page
/// can be a 4 MB, 2000x3000 image - no point holding that for a grid tile).
class LocalPageThumbnail extends StatefulWidget {
  final LocalLibraryStore store;
  final String bookId;
  const LocalPageThumbnail({super.key, required this.store, required this.bookId});

  @override
  State<LocalPageThumbnail> createState() => _LocalPageThumbnailState();
}

class _LocalPageThumbnailState extends State<LocalPageThumbnail> {
  late Future<Uint8List?> _bytes = widget.store.getPage(widget.bookId, 0);

  @override
  void didUpdateWidget(LocalPageThumbnail old) {
    super.didUpdateWidget(old);
    if (old.bookId != widget.bookId) {
      _bytes = widget.store.getPage(widget.bookId, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.store.pageFile(widget.bookId, 0);
    if (file != null) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        cacheWidth: 360,
        errorBuilder: (_, _, _) => const SeriesCover(imageUrl: null),
      );
    }
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snap) =>
          SeriesCover(imageUrl: null, imageBytes: snap.data),
    );
  }
}

class _WatchFolderRow extends StatelessWidget {
  final String? path;
  final VoidCallback onChoose;
  final VoidCallback onStop;
  const _WatchFolderRow({required this.path, required this.onChoose, required this.onStop});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_outlined, size: 16, color: AppColors.text45),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              path == null
                  ? 'Not watching a folder'
                  : 'Watching: $path',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(size: 12, color: AppColors.text60),
            ),
          ),
          TextButton(
            onPressed: path == null ? onChoose : onStop,
            child: Text(path == null ? 'Choose folder' : 'Stop',
                style: AppText.body(size: 12.5, weight: FontWeight.w600, color: AppColors.accentLink)),
          ),
        ],
      ),
    );
  }
}

class _SeriesAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  final bool destructive;
  final VoidCallback onTap;
  const _SeriesAction({
    required this.icon,
    required this.title,
    this.hint,
    this.destructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.dangerText : AppColors.text;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppText.body(size: 15, weight: FontWeight.w600, color: color)),
                  if (hint != null) ...[
                    const SizedBox(height: 3),
                    Text(hint!, style: AppText.body(size: 12, color: AppColors.text45)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool importing;
  final VoidCallback onImport;
  const _EmptyState({required this.importing, required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_zip_outlined, size: 40, color: AppColors.text30),
            const SizedBox(height: 14),
            Text('Nothing imported yet', style: AppText.heading(size: 17)),
            const SizedBox(height: 8),
            Text(
              'Import a CBZ or ZIP file of a manga chapter or comic issue '
              'to read it here, same as anything from a server.',
              textAlign: TextAlign.center,
              style: AppText.body(size: 13, color: AppColors.text45),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: importing ? null : onImport,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Import a file'),
            ),
          ],
        ),
      ),
    );
  }
}
