import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../app/providers.dart';
import '../shared/back_button.dart';
import '../shared/series_cover.dart';
import 'collection_entry.dart';

/// One collection's titles, from whichever servers they live on. Tap to
/// open; long-press or right-click to remove.
class CollectionDetailScreen extends ConsumerWidget {
  final String collectionId;
  const CollectionDetailScreen({super.key, required this.collectionId});

  Future<void> _rename(BuildContext context, WidgetRef ref, String current) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Rename collection'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppText.body(size: 14),
          onSubmitted: (v) => Navigator.pop(d, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(d, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == current) return;
    await ref.read(collectionsStoreProvider).rename(collectionId, name);
    ref.read(collectionsRevisionProvider.notifier).state++;
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Delete collection?'),
        content: Text('"$name" goes; the series in it stay where they are.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text('Delete', style: TextStyle(color: AppColors.dangerText)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(collectionsStoreProvider).delete(collectionId);
    ref.read(collectionsRevisionProvider.notifier).state++;
    if (context.mounted) context.popOrHome(fallback: '/collections');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(collectionsRevisionProvider);
    final collection = ref.watch(collectionsStoreProvider).get(collectionId);

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppScreenHeader(
              title: collection?.name ?? 'Collection',
              onBack: () => context.popOrHome(fallback: '/collections'),
              trailing: collection == null
                  ? null
                  : PopupMenuButton<String>(
                      tooltip: 'Collection options',
                      icon: Icon(Icons.more_horiz_rounded, color: AppColors.text),
                      color: AppColors.card,
                      onSelected: (v) => v == 'rename'
                          ? _rename(context, ref, collection.name)
                          : _delete(context, ref, collection.name),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'delete', child: Text('Delete collection')),
                      ],
                    ),
            ),
            Expanded(
              child: collection == null
                  ? Center(
                      child: Text('This collection no longer exists.',
                          style: AppText.body(color: AppColors.text45)))
                  : collection.seriesIds.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'Nothing here yet. Open any series and tap its '
                              'bookmark button to add it.',
                              textAlign: TextAlign.center,
                              style: AppText.body(color: AppColors.text45),
                            ),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 150,
                            childAspectRatio: 0.56,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 16,
                          ),
                          itemCount: collection.seriesIds.length,
                          itemBuilder: (context, i) => _EntryTile(
                            collectionId: collectionId,
                            entry: collection.seriesIds[i],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  final String collectionId;
  final String entry;
  const _EntryTile({required this.collectionId, required this.entry});

  Future<void> _remove(BuildContext context, WidgetRef ref, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Remove from collection?'),
        content: Text('"$title" stays in your library.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(collectionsStoreProvider).removeSeries(collectionId, entry);
    ref.read(collectionsRevisionProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = ref.watch(collectionEntryProvider(entry));
    final e = resolved.valueOrNull;
    final title = e?.series.title ??
        (resolved.isLoading ? '' : 'Unavailable on this device');

    return PressScale(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: e == null ? null : () => openCollectionEntry(context, ref, e),
        onLongPress: () => _remove(context, ref, title),
        onSecondaryTap: () => _remove(context, ref, title),
        child: MouseRegion(
          cursor: e == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox.expand(
                    child: SeriesCover(
                      imageUrl: e?.series.thumbnailUrl,
                      headers: e?.backend.imageHeaders ?? const {},
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(
                      size: 12,
                      weight: FontWeight.w500,
                      color: e == null ? AppColors.text45 : AppColors.text)),
            ],
          ),
        ),
      ),
    );
  }
}
