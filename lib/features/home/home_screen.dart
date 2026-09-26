import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
import '../../core/history/history_entry.dart';
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

    return Scaffold(
      backgroundColor: AppColors.page,
      extendBody: true,
      body: backendAsync.when(
        loading: () => const _HomeSkeleton(),
        error: (e, st) => AppErrorState(
          error: e,
          onRetry: () => ref.invalidate(activeBackendProvider),
        ),
        data: (backend) =>
            backend == null ? const _NoServerState() : const _HomeBody(),
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

String _typeLabel(ServerType t) => switch (t) {
      ServerType.komga => 'Komga',
      ServerType.kavita => 'Kavita',
      ServerType.suwayomi => 'Suwayomi',
      ServerType.opds => 'OPDS',
    };

/// Komga/Kavita are Western-comic-shaped (issues, not chapters); Suwayomi/OPDS
/// read as manga. Only affects the label word - the data is backend-agnostic.
bool _isComicBackend(ServerType type) =>
    type == ServerType.komga || type == ServerType.kavita;

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

  const _HeroData({
    required this.series,
    required this.backend,
    this.book,
    this.entry,
    this.page = 0,
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
  (DateTime?, int, String?)? _heroKey;

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

    final queues = <String, List<FeedSeries>>{};
    for (final s in feed.inProgress) {
      if (!seen.contains(s.key)) queues.putIfAbsent(s.serverId, () => []).add(s);
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
    try {
      final backend = await ref.read(backendForServerProvider(e.serverId).future);
      if (backend == null) return null;
      final series = await backend.getSeries(e.seriesId);
      final books = await backend.listBooks(e.seriesId);
      final i = books.indexWhere((b) => b.id == e.bookId);
      if (i < 0) return _heroFromSeries(FeedSeries(series, backend));
      // A finished chapter means "continue" is the next one, from its start.
      if (e.completed && i + 1 < books.length) {
        return _HeroData(series: series, backend: backend, book: books[i + 1], entry: e);
      }
      return _HeroData(
          series: series, backend: backend, book: books[i], entry: e, page: e.lastPage);
    } catch (_) {
      return null;
    }
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
            );
            if (_heroFuture == null || _heroKey != key) {
              _heroKey = key;
              _heroFuture = _resolveHeroes(feed, history);
            }
            return FutureBuilder<List<_HeroData>>(
              key: const ValueKey('content'),
              future: _heroFuture,
              builder: (context, heroSnap) {
                final heroes = heroSnap.data ?? const <_HeroData>[];
                final heroKeys = heroes.map((h) => h.key).toSet();
                final visible = feed.inProgress
                    .where((s) => _filter == null || s.serverId == _filter)
                    .where((s) => !heroKeys.contains(s.key))
                    .toList();
                final shelf = orderByRecency(visible, history, activeId);
                final recent = feed.recent
                    .where((r) => _filter == null || r.backend.config.id == _filter)
                    .toList();
                final last = lastReadByKey(history, activeId);
                final topPad = MediaQuery.paddingOf(context).top;

                return ListView(
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
                        onSelect: (id) => setState(() => _filter = id),
                      ),
                    if (feed.unreachable.isNotEmpty)
                      _UnreachableNote(servers: feed.unreachable, onRetry: _refresh),
                    AnimatedSwitcher(
                      duration: Motion.scaled(context, Motion.fast),
                      switchInCurve: Motion.easeOut,
                      child: Column(
                        key: ValueKey(_filter),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (shelf.isNotEmpty)
                            _ContinueShelf(
                              items: shelf,
                              lastBySeries: last,
                              onOpen: _openSeries,
                            ),
                          if (recent.length >= 3)
                            _JustAdded(rows: recent, onOpen: _openSeries),
                          if (shelf.isEmpty && recent.isEmpty && heroes.isEmpty)
                            const _NothingYet(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 120),
                  ],
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

  final _controller = PageController();
  Timer? _timer;
  int _page = 0;
  DateTime _lastTouch = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_every, (_) => _advance());
  }

  void _advance() {
    final n = widget.heroes.length;
    if (!mounted || n < 2 || Motion.reduced(context)) return;
    if (DateTime.now().difference(_lastTouch) < _pauseAfterTouch) return;
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
    final tall = MediaQuery.sizeOf(context).width < 700;
    return SizedBox(
      height: tall ? 452 : 420,
      child: Stack(
        children: [
          Listener(
            onPointerDown: (_) => _lastTouch = DateTime.now(),
            child: NotificationListener<ScrollNotification>(
              onNotification: (_) {
                _lastTouch = DateTime.now();
                return false;
              },
              child: PageView.builder(
                controller: _controller,
                itemCount: n,
                onPageChanged: (p) => setState(() => _page = p),
                itemBuilder: (context, i) => _HeroCard(hero: widget.heroes[i]),
              ),
            ),
          ),
          if (n > 1)
            Positioned(
              left: 24,
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
  }
}

class _HeroCard extends ConsumerWidget {
  final _HeroData hero;
  const _HeroCard({required this.hero});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            ? (series.booksCount == 0 ? 0.0 : series.booksReadCount / series.booksCount)
            : book.progressRatio;
    final pageLabel = positioned
        ? '${page + 1}/${book.pageCount}'
        : book != null && book.pageCount > 0
            ? '${book.readProgressPage ?? 0}/${book.pageCount}'
            : '${series.booksReadCount}/${series.booksCount}';
    final subtitle = positioned
        ? 'Ch. ${formatChapterNumber(book.number)} · page ${page + 1} of ${book.pageCount}'
        : book != null
            ? _plainChapterLabel(book)
            : '${series.booksUnreadCount} unread';
    final type = hero.backend.config.type;
    final tall = MediaQuery.sizeOf(context).width < 700;

    return SizedBox(
      height: tall ? 452 : 420,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SeriesCover(imageUrl: series.thumbnailUrl, headers: hero.backend.imageHeaders),
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
          Positioned(
            left: 24,
            right: 24,
            bottom: 30,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeSlideIn(
                  child: Row(
                    children: [
                      _Pill(
                        label: entry == null
                            ? 'CONTINUE'
                            : 'CONTINUE · ${_ago(entry.timestamp)}',
                        color: AppColors.accentSoft,
                        background: AppColors.accent.withValues(alpha: 0.28),
                      ),
                      const SizedBox(width: 8),
                      _Pill(
                        label: _typeLabel(type).toUpperCase(),
                        color: AppColors.sourceColor(type.name),
                        background: AppColors.sourceColor(type.name).withValues(alpha: 0.16),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 40),
                  child: Text(
                    series.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.largeTitle(size: 42),
                  ),
                ),
                const SizedBox(height: 10),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 80),
                  child: Text(
                    subtitle,
                    maxLines: 1,
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
                                  content: Text(
                                      'Downloading ${_plainChapterLabel(book)}'),
                                  duration: const Duration(seconds: 2),
                                ));
                              },
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(pageLabel,
                              style: AppText.mono(size: 11, color: AppColors.text45)),
                          const SizedBox(height: 7),
                          SizedBox(width: 66, child: _ProgressBar(value: progress)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;
  const _Pill({required this.label, required this.color, required this.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: AppText.mono(size: 9, weight: FontWeight.w600, color: color)),
    );
  }
}

class _ResumeButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _ResumeButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: Material(
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
      ),
    );
  }
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
  final ValueChanged<String?> onSelect;
  const _SourceChips(
      {required this.servers, required this.selected, required this.onSelect});

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
  final VoidCallback onTap;
  const _Chip({required this.label, this.dot, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.scaled(context, Motion.fast),
          curve: Motion.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : AppColors.fillSubtle,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: selected ? AppColors.accent : AppColors.border),
          ),
          child: Row(
            children: [
              if (dot != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
              ],
              AnimatedDefaultTextStyle(
                duration: Motion.scaled(context, Motion.fast),
                style: AppText.body(
                  size: 12.5,
                  weight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.text60,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnreachableNote extends StatelessWidget {
  final List<ServerConfig> servers;
  final VoidCallback onRetry;
  const _UnreachableNote({required this.servers, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 15, color: AppColors.dangerText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Couldn't reach ${servers.map((s) => _typeLabel(s.type)).join(', ')}",
              style: AppText.body(size: 12, color: AppColors.dangerText),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _NothingYet extends StatelessWidget {
  const _NothingYet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 80, 32, 0),
      child: Column(
        children: [
          Icon(Icons.auto_stories_rounded, size: 40, color: AppColors.text30),
          const SizedBox(height: 14),
          Text('Nothing in progress yet', style: AppText.heading(size: 17)),
          const SizedBox(height: 8),
          Text(
            'Open something from your Library and it will show up here, ready to resume.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 13, color: AppColors.text60),
          ),
        ],
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
                  borderRadius: BorderRadius.circular(13),
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
          Container(height: 380, color: AppColors.card),
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
