import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
import '../../core/history/history_entry.dart';
import '../shared/error_state.dart';
import '../shared/series_cover.dart';

/// "Reading Now" - the app's home screen, per the 3a design: an editorial
/// hero for the most recent in-progress title, an "also in progress" shelf,
/// and a "tonight on your servers" list. The persistent bottom nav bar
/// (glass theme, 5 root tabs) lives one level up in GlassNavScaffold.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backendAsync = ref.watch(activeBackendProvider);
    final recent = ref.watch(recentReadingProvider);

    return Scaffold(
      backgroundColor: AppColors.page,
      extendBody: true,
      body: backendAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => AppErrorState(
          error: e,
          onRetry: () => ref.invalidate(activeBackendProvider),
        ),
        data: (backend) {
          if (backend == null) return const _NoServerState();
          return _ReadingNowContent(backend: backend, recent: recent);
        },
      ),
    );
  }
}

class _NoServerState extends StatelessWidget {
  const _NoServerState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined, size: 48, color: AppColors.text45),
            const SizedBox(height: 12),
            Text('No server configured', style: AppText.heading(size: 18)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.push('/settings/servers/new'),
              child: const Text('Add a server'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The resolved hero: a series plus the specific book to resume.
class _HeroData {
  final Series series;
  final Book? book;

  /// The history entry this hero was built from, when there is one.
  final HistoryEntry? entry;

  /// 0-based page to resume on. Differs from `entry.lastPage` when that
  /// chapter was finished and the hero moved on to the next one.
  final int page;

  const _HeroData({required this.series, this.book, this.entry, this.page = 0});
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'JUST NOW';
  if (d.inMinutes < 60) return '${d.inMinutes}M AGO';
  if (d.inHours < 24) return '${d.inHours}H AGO';
  return '${d.inDays}D AGO';
}

class _ReadingNowContent extends StatefulWidget {
  final ReaderBackend backend;

  /// Reading history on this server, newest first - the source of truth for
  /// what "continue" means, since the server only knows what's unread.
  final List<HistoryEntry> recent;
  const _ReadingNowContent({required this.backend, required this.recent});

  @override
  State<_ReadingNowContent> createState() => _ReadingNowContentState();
}

class _ReadingNowContentState extends State<_ReadingNowContent> {
  late Future<List<Series>> _continueReadingFuture;
  late Future<List<_RecentRow>> _recentFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Resolving the hero costs two backend calls, so keep it until the last
  // read entry or the server's top series actually changes - build() runs
  // far more often than that.
  Future<_HeroData?>? _heroFuture;
  (DateTime?, String?)? _heroKey;

  void _load() {
    _continueReadingFuture = widget.backend.continueReading();
    _recentFuture = _loadRecent();
    _heroFuture = null;
  }

  Future<List<_RecentRow>> _loadRecent() async {
    final books = await widget.backend.recentlyAdded();
    final capped = books.take(6).toList();
    final rows = await Future.wait(capped.map((b) async {
      Series? series;
      try {
        series = await widget.backend.getSeries(b.seriesId);
      } catch (_) {
        // Fall back to the book's own title below.
      }
      return _RecentRow(
        book: b,
        seriesTitle: series?.title ?? b.title,
        thumbnailUrl: series?.thumbnailUrl ?? b.thumbnailUrl,
      );
    }));
    return rows;
  }

  Future<_HeroData?> _resolveHero(List<Series> continueReading) async {
    // What was read *last* beats the server's "first unread chapter": for a
    // series read out of order (jumped to ch. 181), the first unread is
    // chapter 1, which is not where anyone left off.
    final last = widget.recent.firstOrNull;
    if (last != null) {
      try {
        final series = await widget.backend.getSeries(last.seriesId);
        final books = await widget.backend.listBooks(last.seriesId);
        final i = books.indexWhere((b) => b.id == last.bookId);
        if (i >= 0) {
          // A finished chapter means "continue" is the next one, from its start.
          if (last.completed && i + 1 < books.length) {
            return _HeroData(series: series, book: books[i + 1], entry: last);
          }
          return _HeroData(series: series, book: books[i], entry: last, page: last.lastPage);
        }
      } catch (_) {
        // Fall through to the server's own idea of "in progress".
      }
    }
    if (continueReading.isEmpty) return null;
    final series = continueReading.first;
    try {
      final books = await widget.backend.listBooks(series.id);
      if (books.isEmpty) return _HeroData(series: series);
      final inProgress = books.firstWhere(
        (b) => !b.completed,
        orElse: () => books.first,
      );
      return _HeroData(series: series, book: inProgress);
    } catch (_) {
      return _HeroData(series: series);
    }
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait([_continueReadingFuture, _recentFuture]);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Series>>(
        future: _continueReadingFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final continueReading = snapshot.data ?? [];
          final key = (widget.recent.firstOrNull?.timestamp, continueReading.firstOrNull?.id);
          if (_heroFuture == null || _heroKey != key) {
            _heroKey = key;
            _heroFuture = _resolveHero(continueReading);
          }
          return FutureBuilder<_HeroData?>(
            future: _heroFuture,
            builder: (context, heroSnapshot) {
              final hero = heroSnapshot.data;
              final lastBySeries = <String, HistoryEntry>{};
              for (final e in widget.recent) {
                lastBySeries.putIfAbsent(e.seriesId, () => e);
              }
              // Most recently read first; series with no local history keep
              // the server's order after them.
              final rest = continueReading.where((s) => s.id != hero?.series.id).toList();
              final read = rest.where((s) => lastBySeries.containsKey(s.id)).toList()
                ..sort((a, b) =>
                    lastBySeries[b.id]!.timestamp.compareTo(lastBySeries[a.id]!.timestamp));
              final shelf = [...read, ...rest.where((s) => !lastBySeries.containsKey(s.id))];
              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (hero != null)
                    _HeroCard(hero: hero, headers: widget.backend.imageHeaders)
                  else
                    const SizedBox(height: 24),
                  if (shelf.isNotEmpty)
                    _AlsoInProgressShelf(
                      series: shelf,
                      lastBySeries: lastBySeries,
                      headers: widget.backend.imageHeaders,
                    ),
                  _TonightList(
                    future: _recentFuture,
                    backendType: widget.backend.config.type,
                    headers: widget.backend.imageHeaders,
                  ),
                  const SizedBox(height: 100),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final _HeroData hero;
  final Map<String, String> headers;

  const _HeroCard({required this.hero, required this.headers});

  @override
  Widget build(BuildContext context) {
    final series = hero.series;
    final book = hero.book;
    final entry = hero.entry;
    final page = hero.page;
    // With a history entry the position is exact (page within the chapter
    // last read); without one it falls back to the server's saved progress.
    final positioned = entry != null && book != null && book.pageCount > 0;
    final progress = positioned
        ? ((page + 1) / book.pageCount).clamp(0.0, 1.0)
        : book == null
            ? (series.booksCount == 0
                ? 0.0
                : series.booksReadCount / series.booksCount)
            : book.progressRatio;
    final pageLabel = positioned
        ? '${page + 1}/${book.pageCount}'
        : book != null && book.pageCount > 0
            ? '${book.readProgressPage ?? 0}/${book.pageCount}'
            : '${series.booksReadCount}/${series.booksCount}';
    final subtitle = positioned
        ? 'Ch. ${_formatNumber(book.number)} · page ${page + 1} of ${book.pageCount}'
        : book != null
            ? 'Ch. ${book.number} · ${book.title}'
            : '${series.booksUnreadCount} unread';

    return SizedBox(
      height: 452,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SeriesCover(imageUrl: series.thumbnailUrl, headers: headers),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  AppColors.page,
                  AppColors.page.withValues(alpha: 0.78),
                  Colors.transparent,
                ],
                stops: const [0.05, 0.36, 0.72],
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 30,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry == null ? 'CONTINUE' : 'CONTINUE · ${_ago(entry.timestamp)}',
                  style: AppText.mono(
                    size: 9,
                    weight: FontWeight.w500,
                    color: AppColors.accentLink,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  series.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.largeTitle(size: 42),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(size: 13.5, color: AppColors.text60),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _ResumeButton(
                      onTap: book == null
                          ? null
                          // push, not go: back from the reader returns here.
                          : () => context.push(
                                '/read/${Uri.encodeComponent(book.id)}'
                                '${entry != null && page > 0 ? '?page=$page' : ''}',
                              ),
                    ),
                    const SizedBox(width: 10),
                    _IconSquareButton(
                      icon: Icons.download_outlined,
                      onTap: book == null ? null : () {},
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(pageLabel,
                            style: AppText.mono(
                                size: 11, color: AppColors.text45)),
                        const SizedBox(height: 7),
                        SizedBox(
                          width: 66,
                          child: _ProgressBar(value: progress),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumeButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _ResumeButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Text('Resume',
                  style: AppText.body(
                      size: 15, weight: FontWeight.w600, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconSquareButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _IconSquareButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.borderStrong),
          ),
          child: Icon(icon, size: 18, color: AppColors.text.withValues(alpha: 0.85)),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double value;
  const _ProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: 3,
        backgroundColor: AppColors.track,
        valueColor: AlwaysStoppedAnimation(AppColors.accent),
      ),
    );
  }
}

class _AlsoInProgressShelf extends StatelessWidget {
  final List<Series> series;

  /// Last-read entry per series id, for the "Ch. N · pX" line.
  final Map<String, HistoryEntry> lastBySeries;
  final Map<String, String> headers;

  const _AlsoInProgressShelf({
    required this.series,
    required this.lastBySeries,
    required this.headers,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Also in progress', style: AppText.heading(size: 17)),
              Text('See all',
                  style: AppText.body(
                      size: 13, weight: FontWeight.w500, color: AppColors.accentLink)),
            ],
          ),
        ),
        SizedBox(
          height: 176,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: series.length,
            itemBuilder: (context, i) {
              final s = series[i];
              final progress =
                  s.booksCount == 0 ? 0.0 : s.booksReadCount / s.booksCount;
              return Padding(
                padding: const EdgeInsets.only(right: 13),
                child: GestureDetector(
                  onTap: () => context
                      .push('/series/${Uri.encodeComponent(s.id)}'),
                  child: SizedBox(
                    width: 104,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                SeriesCover(
                                    imageUrl: s.thumbnailUrl, headers: headers),
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    widthFactor: 1,
                                    child: Container(
                                      height: 3,
                                      color:
                                          Colors.black.withValues(alpha: 0.4),
                                      alignment: Alignment.centerLeft,
                                      child: FractionallySizedBox(
                                        widthFactor: progress.clamp(0, 1),
                                        child: Container(
                                            color: AppColors.accent),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(size: 12, weight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          switch (lastBySeries[s.id]) {
                            final e? =>
                              'Ch. ${_formatNumber(e.bookNumber)} · p${e.lastPage + 1}',
                            null => '${s.booksUnreadCount} unread',
                          },
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.mono(size: 10.5),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RecentRow {
  final Book book;
  final String seriesTitle;
  final String? thumbnailUrl;
  const _RecentRow({required this.book, required this.seriesTitle, this.thumbnailUrl});
}

/// Komga/Kavita/Kapowarr are Western-comic-shaped backends (issues, not
/// chapters); Suwayomi/OPDS read as manga. Only affects the label word -
/// the data itself is backend-agnostic.
bool _isComicBackend(ServerType type) =>
    type == ServerType.komga || type == ServerType.kavita;

/// Komga/Kavita numbers are raw strings from the source library and are
/// often zero-padded for file sorting ("002") - clean that up for display
/// without losing a real fractional part ("3.5").
String _formatNumber(String raw) {
  final n = double.tryParse(raw);
  if (n == null) return raw;
  return n == n.roundToDouble() ? '${n.round()}' : '$n';
}

class _TonightList extends StatelessWidget {
  final Future<List<_RecentRow>> future;
  final ServerType backendType;
  final Map<String, String> headers;
  const _TonightList({required this.future, required this.backendType, required this.headers});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_RecentRow>>(
      future: future,
      builder: (context, snapshot) {
        final rows = snapshot.data ?? [];
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (rows.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tonight on your servers',
                  style: AppText.sectionLabel()),
              const SizedBox(height: 4),
              for (final row in rows)
                _TonightRow(row: row, backendType: backendType, headers: headers),
            ],
          ),
        );
      },
    );
  }
}

class _TonightRow extends StatelessWidget {
  final _RecentRow row;
  final ServerType backendType;
  final Map<String, String> headers;
  const _TonightRow({required this.row, required this.backendType, required this.headers});

  @override
  Widget build(BuildContext context) {
    final isComic = _isComicBackend(backendType);
    final label = isComic
        ? 'ISSUE #${_formatNumber(row.book.number)}'
        : 'CH ${_formatNumber(row.book.number)}';
    return InkWell(
      onTap: () =>
          context.push('/series/${Uri.encodeComponent(row.book.seriesId)}'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              height: 54,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SeriesCover(imageUrl: row.thumbnailUrl, headers: headers),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.seriesTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(size: 14.5, weight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.mono(size: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
