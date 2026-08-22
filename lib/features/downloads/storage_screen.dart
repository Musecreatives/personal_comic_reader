import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

class StorageScreen extends ConsumerStatefulWidget {
  const StorageScreen({super.key});

  @override
  ConsumerState<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends ConsumerState<StorageScreen> {
  @override
  Widget build(BuildContext context) {
    final store = ref.watch(downloadStoreProvider);
    ref.watch(downloadQueueProvider); // rebuild this screen on queue changes

    final tasks = store.listTasks();
    final seriesIds = tasks.map((t) => t.seriesId).toSet().toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Storage')),
      body: ListView(
        children: [
          if (kIsWeb)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Downloads are stored in this browser (IndexedDB). '
                    'Safari in particular may cap or evict this storage under '
                    'space pressure - downloads aren\'t guaranteed to survive '
                    'indefinitely on web.',
                  ),
                ),
              ),
            ),
          ListTile(
            title: const Text('Total downloaded'),
            subtitle: Text(_formatBytes(store.totalSize)),
          ),
          ListTile(
            title: const Text('Clear all downloads'),
            leading: const Icon(Icons.delete_sweep_outlined),
            onTap: tasks.isEmpty
                ? null
                : () async {
                    await store.clearAll();
                    if (mounted) setState(() {});
                  },
          ),
          ListTile(
            title: const Text('Clear page cache'),
            subtitle: const Text('Opportunistic cache from reading, not downloads'),
            leading: const Icon(Icons.cached),
            onTap: () async {
              final cache = ref.read(pageCacheProvider);
              for (final t in tasks) {
                await cache.clearBook(t.bookId);
              }
              if (mounted) setState(() {});
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('By series',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (seriesIds.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No downloads yet.'),
            ),
          ...seriesIds.map((seriesId) {
            final size = store.sizeForSeries(seriesId);
            final seriesTasks = tasks.where((t) => t.seriesId == seriesId);
            final count = seriesTasks.length;
            final title = seriesTasks.first.seriesTitle;
            return ListTile(
              title: Text(title.isEmpty ? 'Series $seriesId' : title),
              subtitle: Text('$count book(s) - ${_formatBytes(size)}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await store.clearSeries(seriesId);
                  if (mounted) setState(() {});
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return '${value.toStringAsFixed(1)} ${units[unitIndex]}';
  }
}
