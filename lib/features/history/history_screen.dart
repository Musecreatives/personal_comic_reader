import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../core/backend/reader_backend.dart';
import '../../core/history/history_entry.dart';
import '../shared/error_state.dart';

/// Local-only reading history (6e), grouped by day. Series titles are
/// resolved lazily per unique seriesId since [HistoryEntry] only stores
/// what the reader has on hand at session-close time.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final backendAsync = ref.watch(activeBackendProvider);
    final entries = ref.watch(historyStoreProvider).list();

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
                  Text('History', style: AppText.largeTitle()),
                  if (entries.isNotEmpty)
                    TextButton(
                      onPressed: () => _confirmClear(context),
                      child: Text('Clear',
                          style: AppText.body(
                              size: 12.5, weight: FontWeight.w600, color: AppColors.dangerText)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: backendAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => AppErrorState(
                    error: e, onRetry: () => ref.invalidate(activeBackendProvider)),
                data: (backend) {
                  if (entries.isEmpty) {
                    return Center(
                      child: Text('Nothing read yet.',
                          style: AppText.body(color: AppColors.text45)),
                    );
                  }
                  return _HistoryList(entries: entries, backend: backend);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Clear history?', style: AppText.body(size: 16, weight: FontWeight.w600)),
        content: Text('This only clears the local log on this device - it does not touch progress already saved on your servers.',
            style: AppText.body(size: 13, color: AppColors.text60)),
        actions: [
          TextButton(onPressed: () => context.pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await ref.read(historyStoreProvider).clear();
              if (context.mounted) {
                context.pop();
                setState(() {});
              }
            },
            child: Text('Clear', style: TextStyle(color: AppColors.dangerText)),
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends StatefulWidget {
  final List<HistoryEntry> entries;
  final ReaderBackend? backend;
  const _HistoryList({required this.entries, required this.backend});

  @override
  State<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<_HistoryList> {
  final Map<String, String> _titleCache = {};
  late Future<void> _resolveFuture;

  @override
  void initState() {
    super.initState();
    _resolveFuture = _resolveTitles();
  }

  Future<void> _resolveTitles() async {
    final backend = widget.backend;
    if (backend == null) return;
    final ids = widget.entries.map((e) => e.seriesId).toSet();
    await Future.wait(ids.map((id) async {
      try {
        final series = await backend.getSeries(id);
        _titleCache[id] = series.title;
      } catch (_) {
        // Leave unresolved - row falls back to the chapter title.
      }
    }));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<HistoryEntry>>{};
    for (final e in widget.entries) {
      final key = _dayLabel(e.timestamp);
      groups.putIfAbsent(key, () => []).add(e);
    }

    return FutureBuilder<void>(
      future: _resolveFuture,
      builder: (context, snapshot) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            for (final key in groups.keys) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
                child: Text(key, style: AppText.body(size: 12, weight: FontWeight.w600, color: AppColors.text.withValues(alpha: 0.8))),
              ),
              for (final entry in groups[key]!) _HistoryRow(entry: entry, seriesTitle: _titleCache[entry.seriesId]),
            ],
          ],
        );
      },
    );
  }

  String _dayLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

class _HistoryRow extends StatelessWidget {
  final HistoryEntry entry;
  final String? seriesTitle;
  const _HistoryRow({required this.entry, required this.seriesTitle});

  @override
  Widget build(BuildContext context) {
    final title = seriesTitle ?? entry.bookTitle;
    final time = TimeOfDay.fromDateTime(entry.timestamp).format(context);
    return InkWell(
      onTap: () => context.push('/series/${Uri.encodeComponent(entry.seriesId)}'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(size: 14, weight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(
                    entry.completed
                        ? 'Ch. ${entry.bookNumber} · finished'
                        : 'Ch. ${entry.bookNumber} · page ${entry.lastPage + 1} of ${entry.pageCount}',
                    style: AppText.body(size: 11, color: AppColors.text45),
                  ),
                ],
              ),
            ),
            if (entry.completed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.suwayomi.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('DONE', style: AppText.mono(size: 9, color: AppColors.suwayomiText)),
              )
            else
              Text(time, style: AppText.mono(size: 10)),
          ],
        ),
      ),
    );
  }
}
