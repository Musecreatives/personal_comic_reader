import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/brand_seal.dart';
import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
import '../../core/history/history_entry.dart';
import '../../core/discovery/recommender.dart';
import '../discovery/discovery_providers.dart';
import '../shared/ink_chip.dart';
import '../shared/error_state.dart';
import '../shared/series_cover.dart';
import 'home_feed.dart';

/// "Reading Now" - the app's home screen, merged across every server: an
/// editorial hero for whatever was read last (anywhere), a shelf of series in
/// progress, and what's new on your servers. The persistent bottom nav bar
/// lives one level up in GlassNavScaffold.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backendAsync = ref.watch(activeBackendProvider);

    final topPad = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: AppColors.page,
      extendBody: true,
      body: Stack(
        children: [
          backendAsync.when(
            loading: () => const _HomeSkeleton(),
            error: (e, st) => AppErrorState(
              error: e,
              onRetry: () => ref.invalidate(activeBackendProvider),
            ),
            data: (backend) =>
                backend == null ? const _NoServerState() : const _HomeBody(),
          ),
          // Edge to edge, Home scrolls under the status bar; a soft scrim
          // keeps headings from colliding with the clock and icons.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topPad,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.page.withValues(alpha: 0.85),
                      AppColors.page.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoServerState extends StatelessWidget {
  const _NoServerState();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      title: 'No server configured',
      message: 'Sign in with the Komga account you were given.',
      // The form opens pre-filled with the public Komga address; its type
      // picker still reaches Suwayomi and OPDS.
      action: FilledButton(
        onPressed: () => context.push('/settings/servers/new'),
        child: const Text('Add Shaddai Komga'),
      ),
    );
  }
}

String _typeLabel(ServerType t) => switch (t) {
      ServerType.komga => 'Komga',
      ServerType.suwayomi => 'Suwayomi',
      ServerType.opds => 'OPDS',
      ServerType.local => 'On This Device',
    };

/// Komga is Western-comic-shaped (issues, not chapters); Suwayomi/OPDS read
/// as manga. Only affects the label word - the data is backend-agnostic.
bool _isComicBackend(ServerType type) => type == ServerType.komga;

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'JUST NOW';
  if (d.inMinutes < 60) return '${d.inMinutes}M AGO';
  if (d.inHours < 24) return '${d.inHours}H AGO';
  return '${d.inDays}D AGO';
}

/// The resolved hero: a series plus the specific book to resume.
class _HeroData {
  final Series series;
  final Book? book;
  final ReaderBackend backend;

  /// The history entry this hero was built from, when there is one.
  final HistoryEntry? entry;

  /// 0-based page to resume on. Differs from `entry.lastPage` when that
  /// chapter was finished and the hero moved on to the next one.
  final int page;

  /// Its server isn't answering: built from [entry] alone so the last read
  /// stays on Home, with Resume off until the server is back.
  final bool offline;

  const _HeroData({
    required this.series,
    required this.backend,
    this.book,
    this.entry,
    this.page = 0,
    this.offline = false,
  });

  String get key => seriesKey(backend.config.id, series.id);
}

class _HomeBody extends ConsumerStatefulWidget {
  const _HomeBody();

  @override
  ConsumerState<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends ConsumerState<_HomeBody> {
  /// Server id to filter the shelves to; null = all sources.
  String? _filter;

  // Resolving the hero costs backend calls, so keep it until the last read
  // entry or the top in-progress series actually changes - build() runs far
  // more often than that.
  Future<List<_HeroData>>? _heroFuture;
  (DateTime?, int, String?, int)? _heroKey;

  /// The last heroes shown. A refresh keeps them up while the new set
  /// resolves; only the very first load waits on a skeleton.
  List<_HeroData>? _lastHeroes;

  static const _maxHeroes = 5;

  /// Up to five different series for the hero carousel: what was read most
  /// recently (distinct series, newest first), then in-progress titles from
  /// the rest of the library, taking turns between servers so comics and
  /// manga both get a slot.
  Future<List<_HeroData>> _resolveHeroes(
      HomeFeed feed, List<HistoryEntry> history) async {
    final activeId = ref.read(activeServerIdProvider);
    final seen = <String>{};
    final wanted = <Future<_HeroData?>>[];

    for (final e in history) {
      if (wanted.length >= 3) break;
      if (seen.add(seriesKey(e.serverId ?? activeId, e.seriesId))) {
        wanted.add(_heroFromHistory(e));
      }
    }

    final stopped = ref.read(stoppedSeriesStoreProvider);
    final lastRead = lastReadByKey(history, activeId);
    final queues = <String, List<FeedSeries>>{};
    for (final s in feed.inProgress) {
      if (seen.contains(s.key)) continue;
      // Series the user stopped reading stay out until read again.
      if (stopped.isStopped(s.key, lastReadAt: lastRead[s.key]?.timestamp)) continue;
      queues.putIfAbsent(s.serverId, () => []).add(s);
    }
    final turns = queues.values.toList();
    var t = 0;
    while (wanted.length < _maxHeroes && turns.any((q) => q.isNotEmpty)) {
      final q = turns[t++ % turns.length];
      if (q.isEmpty) continue;
      final s = q.removeAt(0);
      if (seen.add(s.key)) wanted.add(_heroFromSeries(s));
    }

    return (await Future.wait(wanted)).whereType<_HeroData>().toList();
  }

  // What was read *last* beats the server's "first unread chapter": for a
  // series read out of order (jumped to ch. 181), the first unread is
  // chapter 1, which is not where anyone left off.
  Future<_HeroData?> _heroFromHistory(HistoryEntry e) async {
    ReaderBackend? backend;
    try {
      backend = await ref.read(backendForServerProvider(e.serverId).future);
      if (backend == null) return null;
      final series = await backend.getSeries(e.seriesId);
      final books = await backend.listBooks(e.seriesId);
      final i = books.indexWhere((b) => b.id == e.bookId);
      if (i < 0) return await _heroFromSeries(FeedSeries(series, backend));
      // A finished chapter means "continue" is the next one, from its start.
      if (e.completed && i + 1 < books.length) {
        return _HeroData(series: series, backend: backend, book: books[i + 1], entry: e);
      }
      return _HeroData(
          series: series, backend: backend, book: books[i], entry: e, page: e.lastPage);
    } catch (_) {
      // The server isn't answering: keep what was read last on Home rather
      // than letting it vanish.
      return backend == null ? null : _offlineHero(e, backend);
    }
  }

  /// History has no series title; a download of that series does.
  _HeroData _offlineHero(HistoryEntry e, ReaderBackend backend) {
    final downloaded = ref
        .read(downloadStoreProvider)
        .listTasks()
        .where((t) => t.seriesId == e.seriesId && t.seriesTitle.isNotEmpty)
        .firstOrNull
        ?.seriesTitle;
    return _HeroData(
      series: Series(
        id: e.seriesId,
        libraryId: '',
        title: downloaded ?? e.bookTitle,
        booksCount: 0,
        booksReadCount: 0,
        booksUnreadCount: 0,
      ),
      backend: backend,
      entry: e,
      page: e.lastPage,
      offline: true,
    );
  }

  Future<_HeroData?> _heroFromSeries(FeedSeries s) async {
    try {
      final books = await s.backend.listBooks(s.series.id);
      if (books.isEmpty) return _HeroData(series: s.series, backend: s.backend);
      final next = books.firstWhere((b) => !b.completed, orElse: () => books.first);
      return _HeroData(series: s.series, backend: s.backend, book: next);
    } catch (_) {
      return _HeroData(series: s.series, backend: s.backend);
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(homeFeedProvider);
    setState(() => _heroFuture = null);
    await ref.read(homeFeedProvider.future);
  }

  Future<void> _openSeries(String serverId, String seriesId) async {
    await activateServer(ref, serverId);
    if (mounted) context.push('/series/${Uri.encodeComponent(seriesId)}');
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(homeFeedProvider);
    final history = ref.watch(recentReadingProvider);
    final activeId = ref.watch(activeServerIdProvider);
    final servers = ref.watch(serverListProvider);
    final stoppedRevision = ref.watch(stoppedRevisionProvider);
    final stopped = ref.watch(stoppedSeriesStoreProvider);
    // Cache only: computing recommendations is slow and lives on its own screen.
    final recs = ref.watch(cachedRecommendationsProvider).valueOrNull ?? const [];
    final suwayomiVisible = _filter == null ||
        servers.any((s) => s.id == _filter && s.type == ServerType.suwayomi);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: AnimatedSwitcher(
        duration: Motion.scaled(context, Motion.base),
        switchInCurve: Motion.easeOut,
        child: feedAsync.when(
          loading: () => const _HomeSkeleton(key: ValueKey('skeleton')),
          error: (e, st) => AppErrorState(
            key: const ValueKey('error'),
            error: e,
            onRetry: () => ref.invalidate(homeFeedProvider),
          ),
          data: (feed) {
            final key = (
              history.firstOrNull?.timestamp,
              feed.inProgress.length,
              feed.inProgress.firstOrNull?.key,
              stoppedRevision,
            );
            if (_heroFuture == null || _heroKey != key) {
              _heroKey = key;
              _heroFuture = _resolveHeroes(feed, history);
            }
            return FutureBuilder<List<_HeroData>>(
              key: const ValueKey('content'),
              future: _heroFuture,
              builder: (context, heroSnap) {
                if (heroSnap.connectionState == ConnectionState.done) {
                  _lastHeroes = heroSnap.data ?? const [];
                }
                final ready = _lastHeroes;
                // First load: until the hero resolves the shelves can't
                // tell which series it takes, so they'd show it and then
                // drop it. Hold the skeleton instead.
                if (ready == null) {
                  return const _HomeSkeleton(key: ValueKey('hero-wait'));
                }
                final heroes = ready;
                final heroKeys = heroes.map((h) => h.key).toSet();
                final down = {
                  for (final s in [...feed.unreachable, ...feed.rejected]) s.id
                };
                final filterIsDown = _filter != null && down.contains(_filter);
                final last = lastReadByKey(history, activeId);
                final visible = feed.inProgress
                    .where((s) => _filter == null || s.serverId == _filter)
                    .where((s) => !heroKeys.contains(s.key))
                    .where((s) => !stopped.isStopped(s.key,
                        lastReadAt: last[s.key]?.timestamp))
                    .toList();
                final shelf = orderByRecency(visible, history, activeId);
                final recent = feed.recent
                    .where((r) => _filter == null || r.backend.config.id == _filter)
                    .toList();
                final topPad = MediaQuery.paddingOf(context).top;

                // Any touch on Home (scrolling, reaching for Resume) holds
                // the hero still.
                return Listener(
                  onPointerDown: (_) => _HeroCarouselState.lastTouch = DateTime.now(),
                  child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    if (heroes.isNotEmpty)
                      _HeroCarousel(heroes: heroes)
                    else
                      SizedBox(height: topPad + 20),
                    if (servers.length > 1)
                      _SourceChips(
                        servers: servers,
                        selected: _filter,
                        down: down,
                        onSelect: (id) => setState(() => _filter = id),
                      ),
                    if (feed.rejected.isNotEmpty)
                      _StatusNote(
                        icon: Icons.lock_outline_rounded,
                        color: AppColors.dangerText,
                        message:
                            '${feed.rejected.map((s) => _typeLabel(s.type)).join(' and ')} rejected your login. '
                            'Update the password in Sources & servers.',
                        onRetry: _refresh,
                      ),
                    if (feed.unreachable.isNotEmpty)
                      _StatusNote(
                        icon: Icons.cloud_off_rounded,
                        color: AppColors.warningText,
                        message: outageMessage(
                          down: [for (final s in feed.unreachable) _typeLabel(s.type)],
                          fine: [
                            for (final s in servers)
                              if (s.type != ServerType.local && !down.contains(s.id))
                                _typeLabel(s.type),
                          ],
                        ),
                        onRetry: _refresh,
                      ),
                    AnimatedSwitcher(
                      duration: Motion.scaled(context, Motion.fast),
                      switchInCurve: Motion.easeOut,
                      child: Column(
                        key: ValueKey(_filter),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (filterIsDown)
                            _FilteredDown(
                              label: _typeLabel(servers
                                  .firstWhere((s) => s.id == _filter)
                                  .type),
                              onRetry: _refresh,
                            )
                          else ...[
                            if (shelf.isNotEmpty)
                              _ContinueShelf(
                                items: shelf,
                                lastBySeries: last,
                                onOpen: _openSeries,
                              ),
                            if (recs.length >= 3 && suwayomiVisible)
                              _RecommendedShelf(recs: recs.take(12).toList()),
                            if (recent.length >= 3)
                              _JustAdded(rows: recent, onOpen: _openSeries),
                            if (shelf.isEmpty && recent.isEmpty && heroes.isEmpty)
                              const _NothingYet(),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 120),
                  ],
                ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Swipeable hero over several different series. It advances by itself every
/// few seconds so the top of Home shows more than one title, but never while a
/// finger is on it (or for a while after), and not at all when the system asks
/// for reduced motion.
class _HeroCarousel extends StatefulWidget {
  final List<_HeroData> heroes;
  const _HeroCarousel({required this.heroes});

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  static const _every = Duration(seconds: 7);
  static const _pauseAfterTouch = Duration(seconds: 10);

  /// Last touch anywhere on Home (set by Home's own listener too), so the
  /// hero doesn't change under a thumb on its way to Resume.
  static DateTime lastTouch = DateTime.fromMillisecondsSinceEpoch(0);

  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_every, (_) => _advance());
  }

  void _advance() {
    final n = widget.heroes.length;
    if (!mounted || n < 2 || Motion.reduced(context)) return;
    // A screen reader's focus would be pulled along by the rotation.
    if (MediaQuery.accessibleNavigationOf(context)) return;
    if (DateTime.now().difference(lastTouch) < _pauseAfterTouch) return;
    _controller.animateToPage(
      (_page + 1) % n,
      duration: Motion.scaled(context, const Duration(milliseconds: 520)),
      curve: Motion.drawer,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.heroes.length;
    return LayoutBuilder(builder: (context, box) {
      final split = _heroSplits(box.maxWidth);
      return SizedBox(
      height: _heroHeight(context, split),
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (_) {
              lastTouch = DateTime.now();
              return false;
            },
            child: PageView.builder(
              controller: _controller,
              itemCount: n,
              onPageChanged: (p) => setState(() => _page = p),
              itemBuilder: (context, i) =>
                  _HeroCard(hero: widget.heroes[i], split: split),
            ),
          ),
          if (n > 1)
            Positioned(
              left: split ? 48 : 24,
              bottom: 12,
              child: Row(
                children: [
                  for (var i = 0; i < n; i++)
                    AnimatedContainer(
                      duration: Motion.scaled(context, Motion.base),
                      curve: Motion.easeOut,
                      margin: const EdgeInsets.only(right: 5),
                      width: i == _page ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? AppColors.accentLink
                            : Colors.white.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    });
  }
}

/// Canvas "Android tablet · Home": with room, the hero is text on the left
/// and the cover on the right, instead of a cover cropped to a wide strip.
/// Below this (phones, a portrait tablet beside its rail) the full-bleed
/// cover stays.
bool _heroSplits(double width) => width >= 720;

double _heroHeight(BuildContext context, bool split) => split
    ? 420 + MediaQuery.paddingOf(context).top
    : MediaQuery.sizeOf(context).width < 700
        ? 452
        : 420;

class _HeroCard extends ConsumerWidget {
  final _HeroData hero;
  final bool split;
  const _HeroCard({required this.hero, this.split = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = hero.series;
    final book = hero.book;
    final entry = hero.entry;
    final page = hero.page;
    final offline = hero.offline;
    // With a history entry the position is exact (page within the chapter
    // last read); without one it falls back to the server's saved progress.
    // Offline there is no book: the entry is all there is.
    final positioned = entry != null && book != null && book.pageCount > 0;
    final pages = offline ? entry!.pageCount : book?.pageCount ?? 0;
    final exact = positioned || (offline && pages > 0);
    final progress = exact
        ? ((page + 1) / pages).clamp(0.0, 1.0)
        : book == null
            ? (series.booksCount == 0 ? 0.0 : series.booksReadCount / series.booksCount)
            : book.progressRatio;
    final pageLabel = exact
        ? '${page + 1}/$pages'
        : book != null && book.pageCount > 0
            ? '${book.readProgressPage ?? 0}/${book.pageCount}'
            : '${series.booksReadCount}/${series.booksCount}';
    final type = hero.backend.config.type;
    final subtitle = offline
        ? 'Ch. ${formatChapterNumber(entry!.bookNumber)} · page ${page + 1} of $pages'
            " · ${_typeLabel(type)} isn't answering"
        : positioned
            ? 'Ch. ${formatChapterNumber(book.number)} · page ${page + 1} of ${book.pageCount}'
            : book != null
                ? _plainChapterLabel(book)
                : '${series.booksUnreadCount} unread';
    final sourceColor =
        offline ? AppColors.warning : AppColors.sourceColor(type.name);

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeSlideIn(
          child: Text(
            series.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.largeTitle(size: 42),
          ),
        ),
        const SizedBox(height: 12),
        // Source and recency as one mono line under the title (no badges
        // above it): a dot in the source's colour, or the offline mark.
        FadeSlideIn(
          delay: const Duration(milliseconds: 40),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              if (offline)
                Icon(Icons.cloud_off_rounded, size: 14, color: AppColors.warningText)
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: sourceColor, shape: BoxShape.circle),
                ),
              Text(
                offline
                    ? '${_typeLabel(type).toUpperCase()} · OFFLINE'
                    : _typeLabel(type).toUpperCase(),
                style: AppText.mono(
                    size: 11.5, color: offline ? AppColors.warningText : AppColors.text60),
              ),
              Text(
                entry == null ? '· CONTINUE' : '· CONTINUE · ${_ago(entry.timestamp)}',
                style: AppText.mono(size: 11.5, color: AppColors.text60),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        FadeSlideIn(
          delay: const Duration(milliseconds: 80),
          child: Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(size: 13.5, color: AppColors.text60),
          ),
        ),
        const SizedBox(height: 20),
        FadeSlideIn(
          delay: const Duration(milliseconds: 120),
          child: Row(
            children: [
              _ResumeButton(
                onTap: book == null
                    ? null
                    : () async {
                        await activateServer(ref, hero.backend.config.id);
                        if (!context.mounted) return;
                        // push, not go: back from the reader returns here.
                        context.push(
                          '/read/${Uri.encodeComponent(book.id)}'
                          '${entry != null && page > 0 ? '?page=$page' : ''}',
                        );
                      },
              ),
              const SizedBox(width: 10),
              _IconSquareButton(
                icon: Icons.download_outlined,
                tooltip: 'Download this chapter',
                onTap: book == null
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await ref.read(downloadManagerProvider).enqueueBooks(
                            hero.backend, [book], series.id, series.title);
                        messenger.showSnackBar(SnackBar(
                          content: Text('Downloading ${_plainChapterLabel(book)}'),
                          duration: const Duration(seconds: 2),
                        ));
                      },
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(pageLabel,
                      style: AppText.mono(size: 11, color: AppColors.text60)),
                  const SizedBox(height: 7),
                  SizedBox(width: 66, child: _ProgressBar(value: progress)),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    // Offline the cover can't load; the placeholder stands in.
    final cover = SeriesCover(
      imageUrl: offline ? null : series.thumbnailUrl,
      headers: hero.backend.imageHeaders,
      framed: false,
    );

    if (split) {
      // Drawn depth (DESIGN.md): a flat card panel closed by a 3px ink frame
      // line, no gradients.
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border(bottom: BorderSide(color: AppColors.text, width: 3)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              48, MediaQuery.paddingOf(context).top + 40, 48, 40),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: details),
              const SizedBox(width: 48),
              FadeSlideIn(
                delay: const Duration(milliseconds: 60),
                child: Container(
                  width: 230,
                  height: 330,
                  // Covers stay square with a 2px ink edge.
                  foregroundDecoration: BoxDecoration(
                    border: Border.all(color: AppColors.text, width: 2),
                  ),
                  child: cover,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        cover,
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                AppColors.page,
                AppColors.page.withValues(alpha: 0.82),
                Colors.transparent,
              ],
              stops: const [0.05, 0.40, 0.76],
            ),
          ),
        ),
        Positioned(left: 24, right: 24, bottom: 30, child: details),
      ],
    );
  }
}

/// "Ch. 1" - and the chapter's own title only when it says something more
/// than its number (so "Chapter 1" isn't shown as "Ch. 1 · Chapter 1").
String _plainChapterLabel(Book book) {
  final n = formatChapterNumber(book.number);
  final t = book.title.trim();
  final redundant = t.isEmpty ||
      RegExp('^(ch(apter)?\\.?\\s*)?0*${RegExp.escape(n)}(\\.0+)?\$',
              caseSensitive: false)
          .hasMatch(t);
  return redundant ? 'Ch. $n' : 'Ch. $n · $t';
}

class _ResumeButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _ResumeButton({this.onTap});

  @override
  Widget build(BuildContext context) =>
      InkButton(icon: Icons.play_arrow_rounded, label: 'Resume', filled: true, onTap: onTap, height: 46);
}

class _IconSquareButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _IconSquareButton({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: Tooltip(
        message: tooltip,
        child: Material(
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
        ),
      ),
    );
  }
}

/// A progress bar that fills in from empty when it first appears.
class _ProgressBar extends StatelessWidget {
  final double value;
  const _ProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1)),
      duration: Motion.scaled(context, const Duration(milliseconds: 700)),
      curve: Motion.easeOut,
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: v,
          minHeight: 3,
          backgroundColor: AppColors.track,
          valueColor: AlwaysStoppedAnimation(AppColors.accent),
        ),
      ),
    );
  }
}

/// Filter chips, one per source: "All", then each server by type.
class _SourceChips extends StatelessWidget {
  final List<ServerConfig> servers;
  final String? selected;

  /// Servers not answering (or rejecting the login): their chip is dimmed.
  final Set<String> down;
  final ValueChanged<String?> onSelect;
  const _SourceChips({
    required this.servers,
    required this.selected,
    this.down = const {},
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final typeCounts = <ServerType, int>{};
    for (final s in servers) {
      typeCounts[s.type] = (typeCounts[s.type] ?? 0) + 1;
    }
    String label(ServerConfig s) => typeCounts[s.type]! > 1
        ? '${_typeLabel(s.type)} · ${s.name}'
        : _typeLabel(s.type);

    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
        children: [
          _Chip(label: 'All', selected: selected == null, onTap: () => onSelect(null)),
          for (final s in servers) ...[
            const SizedBox(width: 8),
            _Chip(
              label: label(s),
              dot: AppColors.sourceColor(s.type.name),
              selected: selected == s.id,
              down: down.contains(s.id),
              onTap: () => onSelect(s.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color? dot;
  final bool selected;
  final bool down;
  final VoidCallback onTap;
  const _Chip({
    required this.label,
    this.dot,
    required this.selected,
    this.down = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkChip(
        label: label,
        selected: selected,
        onTap: onTap,
        dot: dot,
        icon: down ? Icons.cloud_off_rounded : null,
        dimmed: down,
      );
}

/// "Suwayomi isn't answering. Komga and your downloads are fine." Says what
/// is down and, as plainly, what still works (canvas "Server not
/// responding"). [down] and [fine] are source labels.
String outageMessage({required List<String> down, required List<String> fine}) {
  String both(List<String> l) => l.length < 2
      ? l.join()
      : '${l.sublist(0, l.length - 1).join(', ')} and ${l.last}';
  final what = down.length == 1
      ? "${down.single} isn't answering."
      : "${both(down)} aren't answering.";
  final ok = fine.isEmpty
      ? 'Your downloads are fine.'
      : '${both(fine)} and your downloads are fine.';
  return '$what $ok';
}

/// One line about a source that needs attention: amber when it is simply
/// down, red when you have to fix something (a rejected login).
class _StatusNote extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  final VoidCallback onRetry;
  const _StatusNote({
    required this.icon,
    required this.color,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: AppText.body(size: 13, color: AppColors.text)),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// The shelves filtered to a server that isn't answering: say so, instead
/// of a false "Nothing in progress yet".
class _FilteredDown extends StatelessWidget {
  final String label;
  final VoidCallback onRetry;
  const _FilteredDown({required this.label, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 0),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.warningText),
          const SizedBox(height: 14),
          Text('$label is offline', style: AppText.heading(size: 17)),
          const SizedBox(height: 8),
          Text(
            "It isn't answering right now. What you've downloaded still opens from Downloads.",
            textAlign: TextAlign.center,
            style: AppText.body(size: 13, color: AppColors.text60),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _NothingYet extends StatelessWidget {
  const _NothingYet();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 56),
      child: EmptyState(
        title: 'Nothing in progress yet',
        message: 'Open something from your Library and it will show up here, ready to resume.',
      ),
    );
  }
}

class _ContinueShelf extends StatelessWidget {
  final List<FeedSeries> items;

  /// Last-read entry per series, for the "Ch. N · pX" line.
  final Map<String, HistoryEntry> lastBySeries;
  final Future<void> Function(String serverId, String seriesId) onOpen;

  const _ContinueShelf({
    required this.items,
    required this.lastBySeries,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 12, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Continue reading', style: AppText.heading(size: 17)),
              TextButton(
                onPressed: () => context.push('/home/in-progress'),
                child: Text('See all',
                    style: AppText.body(
                        size: 13, weight: FontWeight.w500, color: AppColors.accentLink)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 186,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            itemBuilder: (context, i) => FadeSlideIn(
              delay: Duration(milliseconds: 35 * math.min(i, 6)),
              child: Padding(
                padding: const EdgeInsets.only(right: 13),
                child: SeriesShelfCard(
                  item: items[i],
                  last: lastBySeries[items[i].key],
                  onTap: () => onOpen(items[i].serverId, items[i].series.id),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Recommended for you": titles matched to the library's genres, from the
/// last time the Recommended screen ran. Tapping anything opens that screen,
/// where they can be added.
class _RecommendedShelf extends StatelessWidget {
  final List<Recommendation> recs;
  const _RecommendedShelf({required this.recs});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 12, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recommended for you', style: AppText.heading(size: 17)),
              TextButton(
                onPressed: () => context.push('/discover/recommendations'),
                child: Text('See all',
                    style: AppText.body(
                        size: 13, weight: FontWeight.w500, color: AppColors.accentLink)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 186,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: recs.length,
            itemBuilder: (context, i) {
              final r = recs[i];
              return FadeSlideIn(
                delay: Duration(milliseconds: 35 * math.min(i, 6)),
                child: Padding(
                  padding: const EdgeInsets.only(right: 13),
                  child: PressScale(
                    child: GestureDetector(
                      onTap: () => context.push('/discover/recommendations'),
                      behavior: HitTestBehavior.opaque,
                      child: SizedBox(
                        width: 104,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.zero,
                                child: SizedBox.expand(
                                  child: SeriesCover(imageUrl: r.candidate.thumbnailUrl),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(r.candidate.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.body(size: 12, weight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            Text(
                              r.because.isEmpty
                                  ? ''
                                  : r.because.first[0].toUpperCase() +
                                      r.because.first.substring(1),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.mono(size: 10, color: AppColors.accentLink),
                            ),
                          ],
                        ),
                      ),
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

/// A cover with a source dot, progress bar and "Ch. N · pX" line - shared by
/// Home's shelf and the "See all" grid.
class SeriesShelfCard extends StatelessWidget {
  final FeedSeries item;
  final HistoryEntry? last;
  final VoidCallback onTap;
  final double width;
  const SeriesShelfCard({
    super.key,
    required this.item,
    required this.last,
    required this.onTap,
    this.width = 104,
  });

  @override
  Widget build(BuildContext context) {
    final s = item.series;
    final progress = s.booksCount == 0 ? 0.0 : s.booksReadCount / s.booksCount;
    final type = item.backend.config.type;
    final e = last;
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.zero,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      SeriesCover(
                          imageUrl: s.thumbnailUrl, headers: item.backend.imageHeaders),
                      Positioned(
                        top: 7,
                        left: 7,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.sourceColor(type.name),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.black.withValues(alpha: 0.35), width: 1),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: _ProgressBar(value: progress),
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
                e != null
                    ? 'Ch. ${formatChapterNumber(e.bookNumber)} · p${e.lastPage + 1}'
                    : '${s.booksUnreadCount} unread',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.mono(size: 10.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Just added": new chapters and issues as a cover mosaic instead of a list.
/// Titles from comic libraries are often unhelpful ("Volume 01 (2025)"), so
/// the cover carries the recognition. Every six items make one block: a large
/// tile (about 2:3, so a cover is not cropped) beside two stacked small ones,
/// then a row of three; blocks alternate which side the large tile sits on.
/// Any leftover is trimmed to whole rows of three so the grid never ends on a
/// hole.
class _JustAdded extends StatelessWidget {
  final List<FeedRecent> rows;
  final Future<void> Function(String serverId, String seriesId) onOpen;
  const _JustAdded({required this.rows, required this.onOpen});

  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) {
    final blocks = rows.length ~/ 6;
    final rowsOfThree = (rows.length - blocks * 6) ~/ 3;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Just added', style: AppText.heading(size: 17)),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, c) {
            if (c.maxWidth >= 700) return _wideMosaic(c.maxWidth);
            // Cap the mosaic on wide screens so covers stay cover-sized.
            final w = math.min(c.maxWidth, 620.0);
            final cw = (w - 2 * _gap) / 3;
            final th = cw * 1.5;
            var n = 0;

            Widget tile(FeedRecent r, double tw, double tHeight, {bool big = false}) {
              final i = n++;
              return _BentoTile(
                row: r,
                width: tw,
                height: tHeight,
                big: big,
                index: i,
                onTap: () => onOpen(r.backend.config.id, r.seriesId),
              );
            }

            Widget threeRow(List<FeedRecent> r) => Row(children: [
                  for (var j = 0; j < 3; j++) ...[
                    if (j > 0) const SizedBox(width: _gap),
                    tile(r[j], cw, th),
                  ],
                ]);

            final children = <Widget>[];
            for (var b = 0; b < blocks; b++) {
              final r = rows.sublist(b * 6, b * 6 + 6);
              final big = tile(r[0], 2 * cw + _gap, 2 * th + _gap, big: true);
              final stack = Column(children: [
                tile(r[1], cw, th),
                const SizedBox(height: _gap),
                tile(r[2], cw, th),
              ]);
              children.add(Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: b.isEven
                    ? [big, const SizedBox(width: _gap), stack]
                    : [stack, const SizedBox(width: _gap), big],
              ));
              children.add(const SizedBox(height: _gap));
              children.add(threeRow(r.sublist(3)));
              children.add(const SizedBox(height: _gap));
            }
            for (var k = 0; k < rowsOfThree; k++) {
              final start = blocks * 6 + k * 3;
              children.add(threeRow(rows.sublist(start, start + 3)));
              children.add(const SizedBox(height: _gap));
            }
            return SizedBox(
              width: w,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
            );
          }),
        ],
      ),
    );
  }

  /// Desktop/tablet: the same mosaic idea sized to the window - one 2x2
  /// feature tile, the columns beside it filled two-high, then full rows -
  /// with as many ~150px columns as fit, instead of a phone-width block
  /// leaving the rest of the window empty.
  Widget _wideMosaic(double width) {
    final cols = (width / 150).floor().clamp(4, 9);
    // Floored so rounding can never push a row a fraction of a pixel wide.
    final cw = ((width - (cols - 1) * _gap) / cols).floorToDouble();
    final th = cw * 1.5;
    var n = 0;

    Widget tile(FeedRecent r, {bool big = false}) {
      final i = n++;
      return _BentoTile(
        row: r,
        width: big ? 2 * cw + _gap : cw,
        height: big ? 2 * th + _gap : th,
        big: big,
        index: i,
        onTap: () => onOpen(r.backend.config.id, r.seriesId),
      );
    }

    Widget row(Iterable<FeedRecent> items) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (j, r) in items.indexed) ...[
              if (j > 0) const SizedBox(width: _gap),
              tile(r),
            ],
          ],
        );

    final beside = cols - 2;
    final featureBlock = math.min(rows.length, 1 + beside * 2);
    final rest = rows.sublist(featureBlock);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tile(rows.first, big: true),
            const SizedBox(width: _gap),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                row(rows.skip(1).take(beside)),
                const SizedBox(height: _gap),
                row(rows.skip(1 + beside).take(beside)),
              ],
            ),
          ],
        ),
        for (var i = 0; i < rest.length; i += cols) ...[
          const SizedBox(height: _gap),
          row(rest.skip(i).take(cols)),
        ],
      ],
    );
  }
}

class _BentoTile extends StatelessWidget {
  final FeedRecent row;
  final double width;
  final double height;
  final bool big;
  final int index;
  final VoidCallback onTap;
  const _BentoTile({
    required this.row,
    required this.width,
    required this.height,
    required this.big,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final type = row.backend.config.type;
    final n = formatChapterNumber(row.latest.number);
    final label = _isComicBackend(type) ? 'Issue $n' : 'Ch. $n';
    final radius = BorderRadius.circular(big ? 18 : 14);

    return FadeSlideIn(
      delay: Duration(milliseconds: 45 * math.min(index, 8)),
      dy: 14,
      child: PressScale(
        scale: 0.97,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: width,
            height: height,
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SeriesCover(
                      imageUrl: row.thumbnailUrl, headers: row.backend.imageHeaders),
                  // Scrim so the text stays readable on any cover.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.82),
                          Colors.black.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.6],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: AppColors.sourceColor(type.name),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black.withValues(alpha: 0.4)),
                      ),
                    ),
                  ),
                  if (row.count > 1)
                    Positioned(
                      top: 7,
                      right: 7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${row.count} new',
                          style: AppText.mono(
                              size: 9, weight: FontWeight.w600, color: Colors.white),
                        ),
                      ),
                    ),
                  Positioned(
                    left: big ? 14 : 9,
                    right: big ? 14 : 9,
                    bottom: big ? 14 : 9,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          row.seriesTitle,
                          maxLines: big ? 3 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(
                            size: big ? 17 : 11.5,
                            weight: FontWeight.w600,
                            color: Colors.white,
                          ).copyWith(height: 1.15),
                        ),
                        SizedBox(height: big ? 6 : 3),
                        Text(
                          label,
                          style: AppText.mono(
                              size: big ? 11 : 9.5,
                              color: Colors.white.withValues(alpha: 0.72)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder shapes while the feed loads - a gentle pulse instead of a
/// spinner, so the page's structure is there before its content is.
class _HomeSkeleton extends StatefulWidget {
  const _HomeSkeleton({super.key});

  @override
  State<_HomeSkeleton> createState() => _HomeSkeletonState();
}

class _HomeSkeletonState extends State<_HomeSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1000))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget block(double w, double h, {double r = 13}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
              color: AppColors.card, borderRadius: BorderRadius.circular(r)),
        );
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 0.95)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          // Same height as the hero it stands in for, so nothing jumps.
          LayoutBuilder(
            builder: (context, box) => Container(
              height: _heroHeight(context, _heroSplits(box.maxWidth)),
              color: AppColors.card,
            ),
          ),
          const SizedBox(height: 26),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: block(150, 18, r: 6),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 150,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                for (var i = 0; i < 4; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 13),
                    child: block(104, 150),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
