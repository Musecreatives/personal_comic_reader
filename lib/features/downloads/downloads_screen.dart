import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/downloads/download_models.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(downloadQueueProvider);
    final backendAsync = ref.watch(activeBackendProvider);
    final manager = ref.watch(downloadManagerProvider);
    final store = ref.watch(downloadStoreProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            tooltip: 'Storage',
            onPressed: () => context.push('/settings/storage'),
          ),
        ],
      ),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text('Wi-Fi only'),
            subtitle: const Text('Pause downloads on cellular (no effect on web)'),
            value: store.wifiOnly,
            onChanged: (v) => store.setWifiOnly(v),
          ),
          const Divider(height: 1),
          Expanded(
            child: queueAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('$e')),
              data: (tasks) {
                if (tasks.isEmpty) {
                  return const Center(child: Text('Nothing queued.'));
                }
                final backend = backendAsync.valueOrNull;
                return ListView.builder(
                  itemCount: tasks.length,
                  itemBuilder: (context, i) {
                    final task = tasks[i];
                    return _TaskTile(
                      task: task,
                      onPause: () => manager.pause(task.bookId),
                      onResume: backend == null
                          ? null
                          : () => manager.resume(task.bookId, backend),
                      onRetry: backend == null
                          ? null
                          : () => manager.retry(task.bookId, backend),
                      onCancel: () => manager.cancel(task.bookId),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onPause;
  final VoidCallback? onResume;
  final VoidCallback? onRetry;
  final VoidCallback onCancel;

  const _TaskTile({
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onRetry,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: task.progress),
          const SizedBox(height: 4),
          Text(
            task.state == DownloadState.failed
                ? task.error ?? 'Failed'
                : '${task.downloadedPages} / ${task.totalPages} pages - ${task.state.name}',
          ),
        ],
      ),
      trailing: _actionButton(),
    );
  }

  Widget? _actionButton() {
    switch (task.state) {
      case DownloadState.running:
      case DownloadState.queued:
        return IconButton(icon: const Icon(Icons.pause), onPressed: onPause);
      case DownloadState.paused:
        return IconButton(
            icon: const Icon(Icons.play_arrow), onPressed: onResume);
      case DownloadState.failed:
        return IconButton(icon: const Icon(Icons.refresh), onPressed: onRetry);
      case DownloadState.done:
        return IconButton(
            icon: const Icon(Icons.delete_outline), onPressed: onCancel);
    }
  }
}
