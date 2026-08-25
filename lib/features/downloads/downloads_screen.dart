import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../core/backend/reader_backend.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/downloads/download_models.dart';
import '../../core/downloads/download_store.dart';

enum _DlTab { queue, onDevice, acquisition }

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  _DlTab _tab = _DlTab.queue;

  @override
  Widget build(BuildContext context) {
    final queueAsync = ref.watch(downloadQueueProvider);
    final backendAsync = ref.watch(activeBackendProvider);
    final manager = ref.watch(downloadManagerProvider);
    final store = ref.watch(downloadStoreProvider);

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
              child: Text('Downloads', style: AppText.largeTitle()),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.fillSubtle,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: [
                    _TabButton(
                      label: 'Queue',
                      active: _tab == _DlTab.queue,
                      onTap: () => setState(() => _tab = _DlTab.queue),
                    ),
                    _TabButton(
                      label: 'On device',
                      active: _tab == _DlTab.onDevice,
                      onTap: () => setState(() => _tab = _DlTab.onDevice),
                    ),
                    _TabButton(
                      label: 'Acquiring',
                      active: _tab == _DlTab.acquisition,
                      onTap: () => setState(() => _tab = _DlTab.acquisition),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: switch (_tab) {
                _DlTab.queue => _QueueTab(
                    queueAsync: queueAsync,
                    manager: manager,
                    backend: backendAsync.valueOrNull,
                    wifiOnly: store.wifiOnly,
                    onWifiOnlyChanged: store.setWifiOnly,
                  ),
                _DlTab.onDevice => _OnDeviceTab(store: store),
                _DlTab.acquisition => const _AcquisitionTab(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabButton({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: active ? AppColors.fillSubtle : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppText.body(
                size: 12.5,
                weight: FontWeight.w600,
                color: active ? AppColors.textAlt : AppColors.text45,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueTab extends StatelessWidget {
  final AsyncValue<List<DownloadTask>> queueAsync;
  final DownloadManager manager;
  final ReaderBackend? backend;
  final bool wifiOnly;
  final ValueChanged<bool> onWifiOnlyChanged;

  const _QueueTab({
    required this.queueAsync,
    required this.manager,
    required this.backend,
    required this.wifiOnly,
    required this.onWifiOnlyChanged,
  });

  @override
  Widget build(BuildContext context) {
    return queueAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) =>
          Center(child: Text('$e', style: AppText.body(color: AppColors.text60))),
      data: (tasks) {
        final active = tasks
            .where((t) =>
                t.state == DownloadState.running || t.state == DownloadState.queued)
            .length;
        final failed = tasks.where((t) => t.state == DownloadState.failed).length;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              children: [
                Expanded(child: _StatCard(value: '$active', label: 'DOWNLOADING')),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    value: '$failed',
                    label: 'FAILED',
                    valueColor: failed > 0 ? AppColors.dangerText : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Wi-Fi only',
                            style: AppText.body(size: 14, weight: FontWeight.w500)),
                        const SizedBox(height: 3),
                        Text('Pause the queue on cellular',
                            style: AppText.body(size: 10.5, color: AppColors.text45)),
                      ],
                    ),
                  ),
                  Switch(
                    value: wifiOnly,
                    onChanged: onWifiOnlyChanged,
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.accent,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                    child: Text('Nothing queued.',
                        style: AppText.body(color: AppColors.text45))),
              )
            else
              Text('IN THE QUEUE', style: AppText.sectionLabel()),
            const SizedBox(height: 10),
            for (final task in tasks)
              Builder(builder: (context) {
                final b = backend;
                return _TaskCard(
                  task: task,
                  onPause: () => manager.pause(task.bookId),
                  onResume: b == null ? null : () => manager.resume(task.bookId, b),
                  onRetry: b == null ? null : () => manager.retry(task.bookId, b),
                  onCancel: () => manager.cancel(task.bookId),
                );
              }),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color? valueColor;
  const _StatCard({required this.value, required this.label, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppText.heading(size: 20, color: valueColor)),
          const SizedBox(height: 6),
          Text(label, style: AppText.mono(size: 9.5)),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onPause;
  final VoidCallback? onResume;
  final VoidCallback? onRetry;
  final VoidCallback onCancel;

  const _TaskCard({
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onRetry,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isFailed = task.state == DownloadState.failed;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: isFailed ? AppColors.danger.withValues(alpha: 0.07) : AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isFailed ? AppColors.danger.withValues(alpha: 0.22) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(size: 14, weight: FontWeight.w500)),
              ),
              _actionButton(),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            isFailed
                ? (task.error ?? 'Failed')
                : '${task.downloadedPages} / ${task.totalPages} PAGES · ${task.state.name.toUpperCase()}',
            style: AppText.mono(
              size: 9.5,
              color: isFailed ? AppColors.dangerText : AppColors.text45,
            ),
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: task.progress,
              minHeight: 3,
              backgroundColor: AppColors.track,
              valueColor: AlwaysStoppedAnimation(
                  isFailed ? AppColors.danger : AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton() {
    switch (task.state) {
      case DownloadState.running:
      case DownloadState.queued:
        return _MiniIconButton(icon: Icons.pause_rounded, onTap: onPause);
      case DownloadState.paused:
        return _MiniIconButton(icon: Icons.play_arrow_rounded, onTap: onResume);
      case DownloadState.failed:
        return _RetryChip(onTap: onRetry);
      case DownloadState.done:
        return _MiniIconButton(icon: Icons.delete_outline, onTap: onCancel);
    }
  }
}

class _MiniIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _MiniIconButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.fillSubtle,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
            width: 30, height: 30, child: Icon(icon, size: 15, color: AppColors.text)),
      ),
    );
  }
}

class _RetryChip extends StatelessWidget {
  final VoidCallback? onTap;
  const _RetryChip({this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.danger.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text('Retry',
              style: AppText.body(size: 11.5, weight: FontWeight.w600, color: AppColors.dangerText)),
        ),
      ),
    );
  }
}

class _OnDeviceTab extends StatefulWidget {
  final DownloadStore store;
  const _OnDeviceTab({required this.store});

  @override
  State<_OnDeviceTab> createState() => _OnDeviceTabState();
}

class _OnDeviceTabState extends State<_OnDeviceTab> {
  @override
  Widget build(BuildContext context) {
    final tasks = widget.store.listTasks();
    final seriesIds = tasks.map((t) => t.seriesId).toSet().toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_formatBytes(widget.store.totalSize),
                  style: AppText.heading(size: 22)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('ON DEVICE', style: AppText.mono(size: 10)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (seriesIds.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
                child: Text('No downloads yet.',
                    style: AppText.body(color: AppColors.text45))),
          )
        else
          Text('BY SERIES', style: AppText.sectionLabel()),
        const SizedBox(height: 10),
        for (final seriesId in seriesIds) ...[
          Builder(builder: (context) {
            final size = widget.store.sizeForSeries(seriesId);
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
                  _MiniIconButton(
                    icon: Icons.delete_outline,
                    onTap: () async {
                      await widget.store.clearSeries(seriesId);
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ),
            );
          }),
        ],
      ],
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

class _AcquisitionTab extends StatelessWidget {
  const _AcquisitionTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        InkWell(
          onTap: () => context.push('/settings/kapowarr'),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.kapowarr.withValues(alpha: 0.14), AppColors.card],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.kapowarr.withValues(alpha: 0.24)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Kapowarr',
                          style: AppText.body(size: 15, weight: FontWeight.w600)),
                      const SizedBox(height: 5),
                      Text('READ-ONLY ACQUISITION STATUS',
                          style: AppText.mono(size: 9.5, color: AppColors.text45)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: AppColors.text45),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
