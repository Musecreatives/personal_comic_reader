import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
import '../../core/collections/collection.dart';
import '../shared/error_state.dart';
import '../shared/series_cover.dart';

/// Local-only shelves that can pull series from any configured server at
/// once (6d). "Started, not finished" is the one smart collection backed
/// by real data (continueReading()); the design's other smart tiles
/// ("Downloaded & unread", "New since last week") need data this app
/// doesn't track per-series yet, so they're left out rather than faked.
class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(collectionsRevisionProvider);
    final collections = ref.watch(collectionsStoreProvider).list();
    final backendAsync = ref.watch(activeBackendProvider);

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Collections', style: AppText.largeTitle()),
                  Material(
                    color: AppColors.accent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _createCollection(context, ref),
                      child: const SizedBox(
                        width: 34,
                        height: 34,
                        child: Icon(Icons.add, size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Text(
                "Yours, kept on this device. One collection can pull from every server at once.",
                style: AppText.body(size: 12.5, color: AppColors.text60),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  for (final c in collections)
                    _CollectionCard(
                      collection: c,
                      backend: backendAsync.valueOrNull,
                      onDelete: () async {
                        await ref.read(collectionsStoreProvider).delete(c.id);
                        ref.read(collectionsRevisionProvider.notifier).state++;
                      },
                    ),
                  if (collections.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('No collections yet - tap + to make one.',
                          style: AppText.body(color: AppColors.text45)),
                    ),
                  const SizedBox(height: 8),
                  Text('SMART, BUILT FROM YOUR STATE', style: AppText.sectionLabel()),
                  const SizedBox(height: 10),
                  backendAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, st) => AppErrorState(error: e),
                    data: (backend) {
                      if (backend == null) return const SizedBox.shrink();
                      return _StartedNotFinishedTile(backend: backend);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _createCollection(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('New collection', style: AppText.body(size: 16, weight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppText.body(size: 14),
          decoration: const InputDecoration(hintText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => context.pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              await ref.read(collectionsStoreProvider).create(name);
              ref.read(collectionsRevisionProvider.notifier).state++;
              if (context.mounted) context.pop();
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  final LocalCollection collection;
  final ReaderBackend? backend;
  final VoidCallback onDelete;
  const _CollectionCard({required this.collection, required this.backend, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 92,
            child: Builder(builder: (context) {
              final b = backend;
              if (collection.seriesIds.isEmpty || b == null) {
                return DecoratedBox(decoration: BoxDecoration(color: AppColors.canvas));
              }
              return Row(
                children: [
                  for (final id in collection.seriesIds.take(4))
                    Expanded(
                      child: FutureBuilder<Series>(
                        future: b.getSeries(id),
                        builder: (context, snapshot) {
                          return SeriesCover(
                            imageUrl: snapshot.data?.thumbnailUrl,
                            headers: b.imageHeaders,
                          );
                        },
                      ),
                    ),
                ],
              );
            }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 12, 8, 13),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(collection.name, style: AppText.body(size: 15.5, weight: FontWeight.w600)),
                      const SizedBox(height: 5),
                      Text('${collection.seriesIds.length} SERIES', style: AppText.mono(size: 9.5)),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: AppColors.text45),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StartedNotFinishedTile extends StatelessWidget {
  final ReaderBackend backend;
  const _StartedNotFinishedTile({required this.backend});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Series>>(
      future: backend.continueReading(),
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Started, not finished', style: AppText.body(size: 14, weight: FontWeight.w500)),
                    const SizedBox(height: 5),
                    Text(
                      snapshot.connectionState == ConnectionState.waiting
                          ? 'LOADING…'
                          : '$count SERIES',
                      style: AppText.mono(size: 10),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: AppColors.text30),
            ],
          ),
        );
      },
    );
  }
}
