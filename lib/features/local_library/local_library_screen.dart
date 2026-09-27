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

  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['cbz', 'zip', 'cbr', 'rar'],
        allowMultiple: true,
      );
      if (files.isEmpty) return;

      final store = ref.read(localLibraryStoreProvider);
      var ok = 0;
      final errors = <String>[];
      for (final f in files) {
        try {
          final bytes = await f.readAsBytes();
          await importArchive(store: store, fileName: f.name, bytes: bytes);
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
                "CBZ/ZIP archives, whole folders of page images, or loose image "
                "files. Real RAR-based CBR isn't supported yet - convert those "
                'to CBZ first.',
                style: AppText.body(size: 12, color: AppColors.text45),
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
                        final cover = coverBook == null
                            ? null
                            : store.getPage(coverBook.id, 0);
                        return FadeSlideIn(
                          delay: Duration(milliseconds: 30 * (i % 12)),
                          child: GestureDetector(
                            onTap: () => _openSeries(s.id),
                            onLongPress: () => _deleteSeries(s),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SeriesCover(imageUrl: null, imageBytes: cover),
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
