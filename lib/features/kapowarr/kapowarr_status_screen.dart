import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/kapowarr/kapowarr_client.dart';

class KapowarrStatusScreen extends ConsumerWidget {
  const KapowarrStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(kapowarrConfigRevisionProvider);
    final configAsync = ref.watch(kapowarrConfigProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kapowarr'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings/kapowarr/edit'),
          ),
        ],
      ),
      body: configAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('$e')),
        data: (config) {
          if (config == null) {
            return _NotConfigured(
              onSetUp: () => context.push('/settings/kapowarr/edit'),
            );
          }
          return _StatusBody(client: KapowarrClient(config: config));
        },
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
            const Icon(Icons.download_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Kapowarr not connected',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text(
              'Connect Kapowarr to see acquisition status here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
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
          return Center(child: Text('Failed to reach Kapowarr: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (stats, queue, history) = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatsGrid(stats: stats),
              const SizedBox(height: 24),
              Text('Downloading (${queue.length})',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (queue.isEmpty)
                const Text('Nothing downloading right now.')
              else
                ...queue.map((q) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.downloading),
                      title: Text(q.title),
                      subtitle: Text(q.source),
                    )),
              const SizedBox(height: 24),
              Text('Recently downloaded',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (history.isEmpty)
                const Text('No download history yet.')
              else
                ...history.map((h) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(h.success
                          ? Icons.check_circle_outline
                          : Icons.error_outline),
                      title: Text(h.title),
                      subtitle: Text('${h.source} • ${_relativeTime(h.downloadedAt)}'),
                    )),
            ],
          ),
        );
      },
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _StatsGrid extends StatelessWidget {
  final KapowarrStats stats;
  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      ('Volumes', '${stats.volumes}'),
      ('Monitored', '${stats.monitored}'),
      ('Issues', '${stats.issues}'),
      ('Downloaded', '${stats.downloadedIssues}'),
      ('Files', '${stats.files}'),
      ('Size', _formatBytes(stats.totalFileSize)),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.4,
      children: tiles
          .map((t) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(t.$2,
                          style: Theme.of(context).textTheme.titleLarge),
                      Text(t.$1,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
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
