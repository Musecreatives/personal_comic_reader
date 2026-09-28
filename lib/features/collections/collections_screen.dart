import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../core/backend/models.dart';
import '../../core/collections/collection.dart';
import '../shared/back_button.dart';
import '../shared/series_cover.dart';
import 'collection_entry.dart';

/// How many series are in progress across every server.
final _inProgressCountProvider = FutureProvider<int>((ref) async {
  final backends = await ref.watch(allBackendsProvider.future);
  final lists = await Future.wait(backends
      .map((b) => b.continueReading().catchError((_) => <Series>[])));
  return lists.fold<int>(0, (n, l) => n + l.length);
});

/// Your collections - shelves that can pull series from every server at
/// once (6d) - plus "Started, not finished", built from reading state.
class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(collectionsRevisionProvider);
    final collections = ref.watch(collectionsStoreProvider).list();

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppScreenHeader(
              title: 'Collections',
              trailing: Material(
                color: AppColors.accent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => createCollection(context, ref),
                  child: const SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(Icons.add, size: 18, color: Colors.white),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Text(
                'One collection can pull from every server at once.',
                style: AppText.body(size: 12.5, color: AppColors.text60),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    children: [
                      for (final c in collections) _CollectionCard(collection: c),
                      if (collections.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text('No collections yet - tap + to make one.',
                              style: AppText.body(color: AppColors.text45)),
                        ),
                      const SizedBox(height: 8),
                      Text('SMART, BUILT FROM YOUR STATE',
                          style: AppText.sectionLabel()),
                      const SizedBox(height: 10),
                      const _StartedNotFinishedTile(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a name and creates a collection. Returns its id, or null.
Future<String?> createCollection(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text('New collection',
          style: AppText.body(size: 16, weight: FontWeight.w600)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: AppText.body(size: 14),
        decoration: const InputDecoration(hintText: 'Name'),
        onSubmitted: (v) => Navigator.pop(d, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(d, controller.text.trim()),
          child: const Text('Create'),
        ),
      ],
    ),
  );
  if (name == null || name.isEmpty) return null;
  final c = await ref.read(collectionsStoreProvider).create(name);
  ref.read(collectionsRevisionProvider.notifier).state++;
  return c.id;
}

class _CollectionCard extends ConsumerWidget {
  final LocalCollection collection;
  const _CollectionCard({required this.collection});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = collection.seriesIds.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PressScale(
        scale: 0.985,
        child: Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            hoverColor: AppColors.fillHover,
            onTap: () => context.push('/collections/${collection.id}'),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 92,
                    child: n == 0
                        ? ColoredBox(color: AppColors.canvas)
                        : Row(
                            children: [
                              for (final entry in collection.seriesIds.take(4))
                                Expanded(child: _EntryCover(entry)),
                              for (var i = n; i < 4; i++)
                                Expanded(child: ColoredBox(color: AppColors.canvas)),
                            ],
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(15, 12, 12, 13),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(collection.name,
                                  style: AppText.body(
                                      size: 15.5, weight: FontWeight.w600)),
                              const SizedBox(height: 5),
                              Text('$n SERIES', style: AppText.mono(size: 9.5)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            size: 20, color: AppColors.text30),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryCover extends ConsumerWidget {
  final String entry;
  const _EntryCover(this.entry);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(collectionEntryProvider(entry)).valueOrNull;
    return SeriesCover(
      imageUrl: e?.series.thumbnailUrl,
      headers: e?.backend.imageHeaders ?? const {},
    );
  }
}

/// Everything in progress across every server; opens the full list.
class _StartedNotFinishedTile extends ConsumerWidget {
  const _StartedNotFinishedTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(_inProgressCountProvider).valueOrNull;
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        hoverColor: AppColors.fillHover,
        onTap: () => context.push('/home/in-progress'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Started, not finished',
                        style: AppText.body(size: 14, weight: FontWeight.w500)),
                    const SizedBox(height: 5),
                    Text(count == null ? 'LOADING…' : '$count SERIES',
                        style: AppText.mono(size: 10)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: AppColors.text30),
            ],
          ),
        ),
      ),
    );
  }
}
