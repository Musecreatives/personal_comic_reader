import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../core/kapowarr/kapowarr_client.dart';
import '../shared/back_button.dart';

class KapowarrStatusScreen extends ConsumerWidget {
  const KapowarrStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(kapowarrConfigRevisionProvider);
    final configAsync = ref.watch(kapowarrConfigProvider);

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: Row(
                children: [
                  const AppBackButton(),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Kapowarr', style: AppText.largeTitle())),
                  Material(
                    color: AppColors.fillSubtle,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => context.push('/settings/kapowarr/edit'),
                      child: const SizedBox(
                        width: 34,
                        height: 34,
                        child: Icon(Icons.settings_outlined, size: 17, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: configAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) =>
                    Center(child: Text('$e', style: AppText.body(color: AppColors.text60))),
                data: (config) {
                  if (config == null) {
                    return _NotConfigured(
                      onSetUp: () => context.push('/settings/kapowarr/edit'),
                    );
                  }
                  return _StatusBody(client: KapowarrClient(config: config));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  final VoidCallback onSetUp;
  const _NotConfigured({required this.onSetUp});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_outlined, size: 48, color: AppColors.text45),
            const SizedBox(height: 12),
            Text('Kapowarr not connected', style: AppText.heading(size: 18)),
            const SizedBox(height: 4),
            Text(
              'Connect Kapowarr to see acquisition status here.',
              textAlign: TextAlign.center,
              style: AppText.body(color: AppColors.text45),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onSetUp, child: const Text('Set up')),
          ],
        ),
      ),
    );
  }
}

class _StatusBody extends StatefulWidget {
  final KapowarrClient client;
  const _StatusBody({required this.client});

  @override
  State<_StatusBody> createState() => _StatusBodyState();
}

class _StatusBodyState extends State<_StatusBody> {
  late Future<(KapowarrStats, List<KapowarrQueueItem>, List<KapowarrHistoryItem>)>
      _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(KapowarrStats, List<KapowarrQueueItem>, List<KapowarrHistoryItem>)>
      _load() async {
    final stats = await widget.client.getStats();
    final queue = await widget.client.getQueue();
    final history = await widget.client.getHistory();
    return (stats, queue, history);
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
              child: Text('Failed to reach Kapowarr: ${snapshot.error}',
                  style: AppText.body(color: AppColors.text60)));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (stats, queue, history) = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.kapowarr.withValues(alpha: 0.12), AppColors.card],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.kapowarr.withValues(alpha: 0.2)),
                ),
                child: _StatsGrid(stats: stats),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: () => context.push('/settings/kapowarr/volumes'),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.grid_view_rounded, size: 17, color: AppColors.text60),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text('Browse all volumes',
                            style: AppText.body(size: 14, weight: FontWeight.w500)),
                      ),
                      Icon(Icons.chevron_right, size: 18, color: AppColors.text30),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text('ACQUIRING NOW', style: AppText.sectionLabel()),
              const SizedBox(height: 10),
              if (queue.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Nothing downloading right now.',
                      style: AppText.body(color: AppColors.text45)),
                )
              else
                for (final q in queue) _QueueCard(item: q),
              const SizedBox(height: 22),
              Text('LANDED IN KOMGA', style: AppText.sectionLabel()),
              const SizedBox(height: 6),
              if (history.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('No download history yet.',
                      style: AppText.body(color: AppColors.text45)),
                )
              else
                for (final h in history) _HistoryRow(item: h, relativeTime: _relativeTime),
            ],
          ),
        );
      },
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}M AGO';
    if (diff.inHours < 24) return '${diff.inHours}H AGO';
    return '${diff.inDays}D AGO';
  }
}

class _QueueCard extends StatelessWidget {
  final KapowarrQueueItem item;
  const _QueueCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.downloading, size: 18, color: AppColors.kavitaText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(size: 13.5, weight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(item.source.toUpperCase(), style: AppText.mono(size: 9.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final KapowarrHistoryItem item;
  final String Function(DateTime) relativeTime;
  const _HistoryRow({required this.item, required this.relativeTime});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: item.success ? AppColors.suwayomiText : AppColors.dangerText,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(size: 13)),
          ),
          Text(relativeTime(item.downloadedAt), style: AppText.mono(size: 9.5)),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final KapowarrStats stats;
  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      ('${stats.volumes}', 'VOLUMES'),
      ('${stats.monitored}', 'MONITORED'),
      ('${stats.issues}', 'ISSUES'),
      ('${stats.downloadedIssues}', 'DOWNLOADED'),
      ('${stats.files}', 'FILES'),
      (_formatBytes(stats.totalFileSize), 'SIZE'),
    ];
    return Wrap(
      spacing: 22,
      runSpacing: 16,
      children: tiles
          .map((t) => SizedBox(
                width: 88,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.$1, style: AppText.heading(size: 19)),
                    const SizedBox(height: 6),
                    Text(t.$2, style: AppText.mono(size: 9)),
                  ],
                ),
              ))
          .toList(),
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
