import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../core/backend/models.dart';
import '../../core/history/history_entry.dart';
import '../../core/history/history_groups.dart';
import '../shared/series_cover.dart';

/// Reading history, grouped by series: each series is a heading with the
/// chapters read under it. Above that, "New chapters" lists series that
/// have chapters out past the furthest one read.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    ref.watch(historyRevisionProvider);
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
                children: [
                  Expanded(child: Text('History', style: AppText.largeTitle())),
                  if (entries.isNotEmpty)
                    TextButton(
                      onPressed: () => _confirmClear(context),
                      child: Text('Clear',
                          style: AppText.body(
                              size: 12.5,
                              weight: FontWeight.w600,
                              color: AppColors.dangerText)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text('Nothing read yet.',
                          style: AppText.body(color: AppColors.text45)),
                    )
                  : _HistoryBody(entries: entries),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Clear history?',
            style: AppText.body(size: 16, weight: FontWeight.w600)),
        content: Text(
            'This only clears the local log on this device - it does not touch progress already saved on your servers.',
            style: AppText.body(size: 13, color: AppColors.text60)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await ref.read(historyStoreProvider).clear();
              ref.read(historyRevisionProvider.notifier).state++;
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: Text('Clear', style: TextStyle(color: AppColors.dangerText)),
          ),
        ],
      ),
    );
  }
}

/// What the series' own server says about it - fetched per series, since
/// history only records what the reader had on hand when a session ended.
class _SeriesInfo {
  final String title;
  final String? thumbnailUrl;
  final Map<String, String> headers;
  final List<Book> newChapters;
  const _SeriesInfo({
    required this.title,
    required this.thumbnailUrl,
    required this.headers,
    required this.newChapters,
  });
}

class _HistoryBody extends ConsumerStatefulWidget {
  final List<HistoryEntry> entries;
  const _HistoryBody({required this.entries});

  @override
  ConsumerState<_HistoryBody> createState() => _HistoryBodyState();
}

class _HistoryBodyState extends ConsumerState<_HistoryBody> {
  // Checking every series ever read would hammer the servers; the recent
  // ones are the ones worth checking for new chapters.
  static const _resolveLimit = 40;

  late List<HistorySeriesGroup> _groups;
  final Map<String, _SeriesInfo> _info = {};

  @override
  void initState() {
    super.initState();
    _groups = groupHistoryBySeries(widget.entries);
    _resolve();
  }

  @override
  void didUpdateWidget(_HistoryBody old) {
    super.didUpdateWidget(old);
    if (!identical(old.entries, widget.entries)) {
      _groups = groupHistoryBySeries(widget.entries);
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final pending = _groups.take(_resolveLimit).toList();
    // A few at a time: each is a series lookup plus a chapter list.
    for (var i = 0; i < pending.length; i += 6) {
      await Future.wait(pending.skip(i).take(6).map(_resolveOne));
      if (mounted) setState(() {});
    }
  }

  Future<void> _resolveOne(HistorySeriesGroup g) async {
    try {
      final backend =
          await ref.read(backendForServerProvider(g.serverId).future);
      if (backend == null) return;
      final series = await backend.getSeries(g.seriesId);
      var fresh = const <Book>[];
      try {
        final books = await backend.listBooks(g.seriesId);
        fresh = newChaptersSince(books, g.entries.map((e) => e.bookId));
      } catch (_) {
        // Title still shows; just no "new chapters" for this one.
      }
      _info[g.key] = _SeriesInfo(
        title: series.title,
        thumbnailUrl: series.thumbnailUrl,
        headers: backend.imageHeaders,
        newChapters: fresh,
      );
    } catch (_) {
      // Server unreachable or series gone - row falls back to what history
      // recorded.
    }
  }

  @override
  Widget build(BuildContext context) {
    final updated = _groups
        .where((g) => _info[g.key]?.newChapters.isNotEmpty ?? false)
        .toList();

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          // Bottom room for the phone's floating nav bar.
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
          children: [
            if (updated.isNotEmpty) ...[
              const _SectionLabel('NEW CHAPTERS'),
              for (final g in updated)
                _NewChaptersRow(group: g, info: _info[g.key]!),
            ],
            const _SectionLabel('RECENTLY READ'),
            for (final g in _groups)
              _SeriesHistoryCard(group: g, info: _info[g.key]),
          ],
        ),
      ),
    );
  }
}

Future<void> _openSeries(
    BuildContext context, WidgetRef ref, HistorySeriesGroup g) async {
  await activateServer(ref, g.serverId);
  if (context.mounted) {
    context.push('/series/${Uri.encodeComponent(g.seriesId)}');
  }
}

Future<void> _openChapter(BuildContext context, WidgetRef ref, String? serverId,
    String bookId, {int? page}) async {
  await activateServer(ref, serverId);
  if (context.mounted) {
    context.push('/read/${Uri.encodeComponent(bookId)}'
        '${page == null ? '' : '?page=$page'}');
  }
}

String _whenLabel(DateTime t) {
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(t.year, t.month, t.day))
      .inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) {
    return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][t.weekday - 1];
  }
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
      'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[t.month - 1]} ${t.day}${t.year == now.year ? '' : ', ${t.year}'}';
}

String _chapterNumber(String n) => n.replaceFirst(RegExp(r'^0+(?=\d)'), '');

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 0, 10),
        child: Text(text, style: AppText.sectionLabel()),
      );
}

class _Cover extends StatelessWidget {
  final _SeriesInfo? info;
  const _Cover(this.info);

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        height: 62,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SeriesCover(
            imageUrl: info?.thumbnailUrl,
            headers: info?.headers ?? const {},
          ),
        ),
      );
}

class _NewChaptersRow extends ConsumerWidget {
  final HistorySeriesGroup group;
  final _SeriesInfo info;
  const _NewChaptersRow({required this.group, required this.info});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final next = info.newChapters.first;
    final n = info.newChapters.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          hoverColor: AppColors.fillHover,
          onTap: () => _openChapter(context, ref, group.serverId, next.id),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
            ),
            child: Row(
              children: [
                _Cover(info),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(info.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(size: 14.5, weight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        'Up next: Ch. ${_chapterNumber(next.number)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(size: 12, color: AppColors.text60),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('$n NEW',
                      style: AppText.mono(size: 9.5, color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One series: its title as the heading, the chapters read underneath.
class _SeriesHistoryCard extends ConsumerStatefulWidget {
  final HistorySeriesGroup group;
  final _SeriesInfo? info;
  const _SeriesHistoryCard({required this.group, required this.info});

  @override
  ConsumerState<_SeriesHistoryCard> createState() => _SeriesHistoryCardState();
}

class _SeriesHistoryCardState extends ConsumerState<_SeriesHistoryCard> {
  static const _collapsedCount = 3;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final info = widget.info;
    final count = g.entries.length;
    final shown =
        _expanded ? g.entries : g.entries.take(_collapsedCount).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            hoverColor: AppColors.fillHover,
            onTap: () => _openSeries(context, ref, g),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
              child: Row(
                children: [
                  _Cover(info),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          // Until the server answers, the chapter title is
                          // the best name history has.
                          info?.title ?? g.entries.first.bookTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(size: 15, weight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_whenLabel(g.lastRead)} · '
                          '$count chapter${count == 1 ? '' : 's'} read',
                          style: AppText.mono(size: 10, color: AppColors.text45),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 20, color: AppColors.text30),
                ],
              ),
            ),
          ),
          for (final e in shown) _ChapterRow(entry: e),
          if (count > _collapsedCount)
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                alignment: Alignment.center,
                child: Text(
                  _expanded
                      ? 'Show less'
                      : 'Show ${count - _collapsedCount} more',
                  style: AppText.body(
                      size: 12.5,
                      weight: FontWeight.w600,
                      color: AppColors.accentLink),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChapterRow extends ConsumerWidget {
  final HistoryEntry entry;
  const _ChapterRow({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = entry;
    return InkWell(
      hoverColor: AppColors.fillHover,
      onTap: () => _openChapter(context, ref, e.serverId, e.bookId,
          page: e.completed ? null : e.lastPage),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              child: Text('CH ${_chapterNumber(e.bookNumber)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.mono(size: 10, color: AppColors.accentLink)),
            ),
            Expanded(
              child: Text(
                e.completed
                    ? 'Finished'
                    : 'Page ${e.lastPage + 1} of ${e.pageCount}',
                style: AppText.body(size: 13, color: AppColors.text60),
              ),
            ),
            if (e.completed)
              Icon(Icons.check_rounded, size: 16, color: AppColors.suwayomiText)
            else
              Text(TimeOfDay.fromDateTime(e.timestamp).format(context),
                  style: AppText.mono(size: 10)),
          ],
        ),
      ),
    );
  }
}
