import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
import '../shared/error_state.dart';
import '../shared/series_cover.dart';
import 'reading_now_dock.dart';

/// "Reading Now" - the app's home screen, per the 3a design: an editorial
/// hero for the most recent in-progress title, an "also in progress" shelf,
/// a "tonight on your servers" list, and the persistent bottom dock.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backendAsync = ref.watch(activeBackendProvider);

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
          return _ReadingNowContent(backend: backend);
        },
      ),
      bottomNavigationBar: ReadingNowDock(
        active: DockTab.reading,
        onLibraryTap: () async {
          final backend = backendAsync.valueOrNull;
          if (backend == null) return;
          final libraries = await backend.listLibraries();
          if (libraries.isEmpty || !context.mounted) return;
          context.push('/library/${Uri.encodeComponent(libraries.first.id)}');
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
  const _HeroData({required this.series, this.book});
}

class _ReadingNowContent extends StatefulWidget {
  final ReaderBackend backend;
  const _ReadingNowContent({required this.backend});

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

  void _load() {
    _continueReadingFuture = widget.backend.continueReading();
    _recentFuture = _loadRecent();
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
      return _RecentRow(book: b, seriesTitle: series?.title ?? b.title);
    }));
    return rows;
  }

  Future<_HeroData?> _resolveHero(List<Series> continueReading) async {
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
          return FutureBuilder<_HeroData?>(
            future: _resolveHero(continueReading),
            builder: (context, heroSnapshot) {
              final hero = heroSnapshot.data;
              final shelf = continueReading.length > 1
                  ? continueReading.sublist(1)
                  : <Series>[];
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
                      headers: widget.backend.imageHeaders,
                    ),
                  _TonightList(future: _recentFuture),
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
    final progress = book == null
        ? (series.booksCount == 0
            ? 0.0
            : series.booksReadCount / series.booksCount)
        : book.progressRatio;
    final pageLabel = book != null && book.pageCount > 0
        ? '${book.readProgressPage ?? 0}/${book.pageCount}'
        : '${series.booksReadCount}/${series.booksCount}';
    final subtitle = book != null
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
                  'CONTINUE',
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
                          : () => context.go('/read/${Uri.encodeComponent(book.id)}'),
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
  final Map<String, String> headers;

  const _AlsoInProgressShelf({required this.series, required this.headers});

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
                          '${s.booksUnreadCount} unread',
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
  const _RecentRow({required this.book, required this.seriesTitle});
}

class _TonightList extends StatelessWidget {
  final Future<List<_RecentRow>> future;
  const _TonightList({required this.future});

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
                _TonightRow(row: row),
            ],
          ),
        );
      },
    );
  }
}

class _TonightRow extends StatelessWidget {
  final _RecentRow row;
  const _TonightRow({required this.row});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () =>
          context.push('/series/${Uri.encodeComponent(row.book.seriesId)}'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SizedBox(
              width: 58,
              child: Text(
                'CH ${row.book.number}',
                style: AppText.mono(size: 10, color: AppColors.accentLink),
              ),
            ),
            Expanded(
              child: Text(
                row.seriesTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(size: 15.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
