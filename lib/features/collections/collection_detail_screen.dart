import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../backends/suwayomi/suwayomi_backend.dart';
import '../../core/collections/collection.dart';
import '../shared/back_button.dart';
import '../shared/series_cover.dart';
import 'collection_entry.dart';
import 'migrate_sheet.dart';

Future<void> renameCollection(
    BuildContext context, WidgetRef ref, String id, String current) async {
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
  await ref.read(collectionsStoreProvider).rename(id, name);
  ref.read(collectionsRevisionProvider.notifier).state++;
}

/// Returns whether it was deleted.
Future<bool> deleteCollection(
    BuildContext context, WidgetRef ref, String id, String name) async {
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
  if (ok != true) return false;
  await ref.read(collectionsStoreProvider).delete(id);
  ref.read(collectionsRevisionProvider.notifier).state++;
  return true;
}

/// One collection's titles, from whichever servers they live on. Tap to
/// open; long-press or right-click for actions (fetch chapters, migrate to
/// another extension, move, remove). Select mode applies those to several.
class CollectionDetailScreen extends ConsumerStatefulWidget {
  final String collectionId;
  const CollectionDetailScreen({super.key, required this.collectionId});

  @override
  ConsumerState<CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends ConsumerState<CollectionDetailScreen> {
  Set<String>? _selected; // non-null while selecting
  bool _working = false;

  String get _id => widget.collectionId;

  void _snack(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  void _changed() => ref.read(collectionsRevisionProvider.notifier).state++;

  /// Refreshes chapter lists from the source for Suwayomi titles; other
  /// servers find new chapters by scanning their own folders.
  Future<void> _fetchChapters(List<String> entries) async {
    setState(() => _working = true);
    var done = 0, skipped = 0, failed = 0;
    for (final entry in entries) {
      final e = await ref.read(collectionEntryProvider(entry).future);
      final backend = e?.backend;
      if (backend is! SuwayomiBackend) {
        skipped++;
        continue;
      }
      try {
        await backend.refreshChapters(e!.series.id);
        ref.invalidate(collectionEntryProvider(entry));
        done++;
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _working = false);
    _snack([
      'Fetched chapters for $done',
      if (skipped > 0) '$skipped not on Suwayomi (their server scans for new ones)',
      if (failed > 0) '$failed failed',
    ].join(' · '));
  }

  Future<void> _move(List<String> entries) async {
    final store = ref.read(collectionsStoreProvider);
    final others = store.list().where((c) => c.id != _id).toList();
    if (others.isEmpty) {
      _snack('Make another collection first.');
      return;
    }
    final target = await showModalBottomSheet<LocalCollection>(
      context: context,
      backgroundColor: AppColors.card,
      builder: (s) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Move to', style: AppText.body(size: 15, weight: FontWeight.w600)),
            ),
            for (final c in others)
              ListTile(
                title: Text(c.name),
                trailing: Text('${c.seriesIds.length}', style: AppText.mono(size: 10)),
                onTap: () => Navigator.pop(s, c),
              ),
          ],
        ),
      ),
    );
    if (target == null) return;
    for (final entry in entries) {
      await store.addSeries(target.id, entry);
      await store.removeSeries(_id, entry);
    }
    _changed();
    if (mounted) _snack('Moved ${entries.length} to ${target.name}');
  }

  Future<void> _remove(List<String> entries) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(entries.length == 1
            ? 'Remove from collection?'
            : 'Remove ${entries.length} from collection?'),
        content: const Text('They stay in your library.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    final store = ref.read(collectionsStoreProvider);
    for (final entry in entries) {
      await store.removeSeries(_id, entry);
    }
    _changed();
  }

  Future<void> _migrate(String entry) async {
    final e = await ref.read(collectionEntryProvider(entry).future);
    final backend = e?.backend;
    if (e == null || backend is! SuwayomiBackend || !mounted) return;
    final newId = await showMigrateSheet(context, backend, e.series);
    if (newId == null) return;
    await ref.read(collectionsStoreProvider).replaceEverywhere(
        entry, collectionEntry(backend.config.portableKey, '$newId'));
    _changed();
    if (mounted) _snack('Migrated "${e.series.title}"');
  }

  Future<void> _actions(String entry, ResolvedEntry? e) async {
    final suwayomi = e?.backend is SuwayomiBackend;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      builder: (s) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (e != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                child: Text(e.series.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(size: 15, weight: FontWeight.w600)),
              ),
            if (e != null)
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('Open'),
                onTap: () => Navigator.pop(s, 'open'),
              ),
            if (suwayomi) ...[
              ListTile(
                leading: const Icon(Icons.sync_rounded),
                title: const Text('Fetch chapters'),
                subtitle: const Text('Check the source for new chapters now'),
                onTap: () => Navigator.pop(s, 'fetch'),
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz_rounded),
                title: const Text('Migrate to another extension'),
                subtitle: Text(e!.series.sourceName == null
                    ? 'Same title, different source'
                    : 'Now on ${e.series.sourceName}'),
                onTap: () => Navigator.pop(s, 'migrate'),
              ),
            ],
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: const Text('Move to another collection'),
              onTap: () => Navigator.pop(s, 'move'),
            ),
            ListTile(
              leading: Icon(Icons.remove_circle_outline, color: AppColors.dangerText),
              title: const Text('Remove from collection'),
              onTap: () => Navigator.pop(s, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'open':
        openCollectionEntry(context, ref, e!);
      case 'fetch':
        _fetchChapters([entry]);
      case 'migrate':
        _migrate(entry);
      case 'move':
        _move([entry]);
      case 'remove':
        _remove([entry]);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(collectionsRevisionProvider);
    final collection = ref.watch(collectionsStoreProvider).get(_id);
    final selected = _selected;
    final entries = collection?.seriesIds ?? const <String>[];

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppScreenHeader(
              title: selected != null
                  ? '${selected.length} selected'
                  : collection?.name ?? 'Collection',
              onBack: selected != null
                  ? () => setState(() => _selected = null)
                  : () => context.popOrHome(fallback: '/collections'),
              trailing: collection == null
                  ? null
                  : selected != null
                      ? TextButton(
                          onPressed: () => setState(() => _selected =
                              selected.length == entries.length ? {} : {...entries}),
                          child: Text(selected.length == entries.length
                              ? 'Select none'
                              : 'Select all'),
                        )
                      : PopupMenuButton<String>(
                          tooltip: 'Collection options',
                          icon: Icon(Icons.more_horiz_rounded, color: AppColors.text),
                          color: AppColors.card,
                          onSelected: (v) async {
                            switch (v) {
                              case 'select':
                                setState(() => _selected = {});
                              case 'fetch':
                                _fetchChapters(entries);
                              case 'rename':
                                renameCollection(context, ref, _id, collection.name);
                              case 'delete':
                                if (await deleteCollection(
                                        context, ref, _id, collection.name) &&
                                    context.mounted) {
                                  context.popOrHome(fallback: '/collections');
                                }
                            }
                          },
                          itemBuilder: (_) => [
                            if (entries.isNotEmpty) ...const [
                              PopupMenuItem(value: 'select', child: Text('Select titles')),
                              PopupMenuItem(
                                  value: 'fetch', child: Text('Fetch chapters for all')),
                            ],
                            const PopupMenuItem(value: 'rename', child: Text('Rename')),
                            const PopupMenuItem(
                                value: 'delete', child: Text('Delete collection')),
                          ],
                        ),
            ),
            if (_working) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: collection == null
                  ? Center(
                      child: Text('This collection no longer exists.',
                          style: AppText.body(color: AppColors.text45)))
                  : entries.isEmpty
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
                            childAspectRatio: 0.52,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 16,
                          ),
                          itemCount: entries.length,
                          itemBuilder: (context, i) {
                            final entry = entries[i];
                            return _EntryTile(
                              entry: entry,
                              selected: selected?.contains(entry),
                              onTap: (e) {
                                if (selected != null) {
                                  setState(() => selected.contains(entry)
                                      ? selected.remove(entry)
                                      : selected.add(entry));
                                } else if (e != null) {
                                  openCollectionEntry(context, ref, e);
                                }
                              },
                              onMenu: (e) => _actions(entry, e),
                            );
                          },
                        ),
            ),
            if (selected != null && selected.isNotEmpty)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed:
                            _working ? null : () => _fetchChapters(selected.toList()),
                        icon: const Icon(Icons.sync_rounded, size: 18),
                        label: const Text('Fetch chapters'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await _move(selected.toList());
                          if (mounted) setState(() => _selected = null);
                        },
                        icon: const Icon(Icons.drive_file_move_outline, size: 18),
                        label: const Text('Move'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await _remove(selected.toList());
                          if (mounted) setState(() => _selected = null);
                        },
                        icon: const Icon(Icons.remove_circle_outline, size: 18),
                        label: const Text('Remove'),
                      ),
                    ],
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
  final String entry;

  /// Null when not selecting.
  final bool? selected;
  final void Function(ResolvedEntry? e) onTap;
  final void Function(ResolvedEntry? e) onMenu;
  const _EntryTile({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = ref.watch(collectionEntryProvider(entry));
    final e = resolved.valueOrNull;
    final title = e?.series.title ??
        (resolved.isLoading ? '' : 'Unavailable on this device');
    final isSelected = selected ?? false;

    return PressScale(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(e),
        onLongPress: () => onMenu(e),
        onSecondaryTap: () => onMenu(e),
        child: MouseRegion(
          cursor: e == null && selected == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SeriesCover(
                        imageUrl: e?.series.thumbnailUrl,
                        headers: e?.backend.imageHeaders ?? const {},
                      ),
                    ),
                    if (selected != null)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: isSelected
                              ? AppColors.accent.withValues(alpha: 0.25)
                              : Colors.black.withValues(alpha: 0.15),
                          border: Border.all(
                            color: isSelected ? AppColors.accent : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        alignment: Alignment.topRight,
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 22,
                          color: isSelected ? AppColors.accent : Colors.white70,
                        ),
                      ),
                  ],
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
              if (e?.series.sourceName != null)
                Text(e!.series.sourceName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.mono(size: 9, color: AppColors.text45)),
            ],
          ),
        ),
      ),
    );
  }
}
