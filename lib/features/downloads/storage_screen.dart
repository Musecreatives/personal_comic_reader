import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
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
    // Largest series first, matching the design's "LARGEST ON DEVICE" list.
    seriesIds.sort((a, b) =>
        store.sizeForSeries(b).compareTo(store.sizeForSeries(a)));

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
          children: [
            Text('Storage', style: AppText.largeTitle(size: 24)),
            const SizedBox(height: 18),
            if (kIsWeb)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.kavita.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.kavita.withValues(alpha: 0.28)),
                ),
                child: Text(
                  'Downloads are stored in this browser (IndexedDB). Safari in '
                  'particular may cap or evict this storage under space pressure - '
                  "downloads aren't guaranteed to survive indefinitely on web.",
                  style: AppText.body(size: 11.5, color: AppColors.kavitaOnDark),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_formatBytes(store.totalSize), style: AppText.heading(size: 26)),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('TOTAL DOWNLOADED', style: AppText.mono(size: 10)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.cached,
                    label: 'Clear page cache',
                    onTap: () async {
                      final cache = ref.read(pageCacheProvider);
                      for (final t in tasks) {
                        await cache.clearBook(t.bookId);
                      }
                      if (mounted) setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.delete_sweep_outlined,
                    label: 'Remove all',
                    danger: true,
                    onTap: tasks.isEmpty
                        ? null
                        : () async {
                            await store.clearAll();
                            if (mounted) setState(() {});
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (seriesIds.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                    child: Text('No downloads yet.',
                        style: AppText.body(color: AppColors.text45))),
              )
            else
              Text('LARGEST ON DEVICE', style: AppText.sectionLabel()),
            const SizedBox(height: 10),
            for (final seriesId in seriesIds)
              Builder(builder: (context) {
                final size = store.sizeForSeries(seriesId);
                final seriesTasks = tasks.where((t) => t.seriesId == seriesId);
                final count = seriesTasks.length;
                final title = seriesTasks.first.seriesTitle;
                return Container(
                  margin: const EdgeInsets.only(bottom: 9),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title.isEmpty ? 'Series $seriesId' : title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.body(size: 14, weight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            Text('$count BOOK(S) · ${_formatBytes(size)}',
                                style: AppText.mono(size: 9.5)),
                          ],
                        ),
                      ),
                      Material(
                        color: AppColors.fillSubtle,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () async {
                            await store.clearSeries(seriesId);
                            if (mounted) setState(() {});
                          },
                          child: SizedBox(
                            width: 30,
                            height: 30,
                            child: Icon(Icons.delete_outline,
                                size: 15, color: AppColors.text),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
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

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback? onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    this.danger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.dangerText : AppColors.text;
    return Material(
      color: danger ? AppColors.danger.withValues(alpha: 0.12) : AppColors.fillSubtle,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: danger
                ? Border.all(color: AppColors.danger.withValues(alpha: 0.3))
                : Border.all(color: AppColors.borderStrong),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 7),
              Text(label, style: AppText.body(size: 12.5, weight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
