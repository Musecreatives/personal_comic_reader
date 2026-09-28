import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../backends/suwayomi/suwayomi_backend.dart';
import '../../core/discovery/recommender.dart';
import '../../core/kapowarr/kapowarr_client.dart';
import '../discovery/discovery_providers.dart';
import '../shared/series_cover.dart';
import 'source_showcase.dart';

// ---------------------------------------------------------------------------
// Shared preview sheet
// ---------------------------------------------------------------------------

/// A look at something before you take it: cover, title, whatever details the
/// caller loads, and one button to acquire it. After acquiring, the button
/// becomes a second action (open it) instead of leaving the sheet.
Future<void> showAcquireSheet(
  BuildContext context, {
  required String coverUrl,
  required String title,
  required String subtitle,
  required Widget details,
  required String actionLabel,
  required Future<void> Function() onAction,
  required String doneLabel,
  required VoidCallback onDone,
  bool alreadyHave = false,
  String alreadyHaveLabel = 'Already added',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: Motion.sheetStyle,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => _AcquireSheet(
      coverUrl: coverUrl,
      title: title,
      subtitle: subtitle,
      details: details,
      actionLabel: actionLabel,
      onAction: onAction,
      doneLabel: doneLabel,
      onDone: () {
        Navigator.pop(sheetContext);
        onDone();
      },
      alreadyHave: alreadyHave,
      alreadyHaveLabel: alreadyHaveLabel,
    ),
  );
}

class _AcquireSheet extends StatefulWidget {
  final String coverUrl;
  final String title;
  final String subtitle;
  final Widget details;
  final String actionLabel;
  final Future<void> Function() onAction;
  final String doneLabel;
  final VoidCallback onDone;
  final bool alreadyHave;
  final String alreadyHaveLabel;
  const _AcquireSheet({
    required this.coverUrl,
    required this.title,
    required this.subtitle,
    required this.details,
    required this.actionLabel,
    required this.onAction,
    required this.doneLabel,
    required this.onDone,
    required this.alreadyHave,
    required this.alreadyHaveLabel,
  });

  @override
  State<_AcquireSheet> createState() => _AcquireSheetState();
}

class _AcquireSheetState extends State<_AcquireSheet> {
  bool _busy = false;
  bool _done = false;
  String? _error;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onAction();
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't add it: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.text30,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 96,
                          height: 140,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SeriesCover(imageUrl: widget.coverUrl),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.title,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.heading(size: 20)),
                              const SizedBox(height: 8),
                              Text(widget.subtitle,
                                  style: AppText.mono(size: 10.5, color: AppColors.text60)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    widget.details,
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_error!,
                          style: AppText.body(size: 12, color: AppColors.dangerText)),
                    ),
                  FilledButton(
                    onPressed: widget.alreadyHave || _busy
                        ? null
                        : (_done ? widget.onDone : _run),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(widget.alreadyHave
                            ? widget.alreadyHaveLabel
                            : (_done ? widget.doneLabel : widget.actionLabel)),
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

/// Description text that shows a few lines and expands on tap.
class _Expandable extends StatefulWidget {
  final String text;
  const _Expandable(this.text);

  @override
  State<_Expandable> createState() => _ExpandableState();
}

class _ExpandableState extends State<_Expandable> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty) {
      return Text('No description.',
          style: AppText.body(size: 13, color: AppColors.text45));
    }
    return GestureDetector(
      onTap: () => setState(() => _open = !_open),
      child: AnimatedSize(
        duration: Motion.scaled(context, Motion.base),
        curve: Motion.easeOut,
        alignment: Alignment.topCenter,
        child: Text(
          widget.text,
          maxLines: _open ? null : 5,
          overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis,
          style: AppText.body(size: 13, color: AppColors.text60),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Manga: search Suwayomi's sources
// ---------------------------------------------------------------------------

class _Hit {
  final int id;
  final String title;
  final String thumbnailUrl;
  final String sourceId;
  const _Hit(this.id, this.title, this.thumbnailUrl, this.sourceId);
}

/// Searches the online sources installed in Suwayomi (not your library): pick
/// "Your sources" (the ones your library mostly comes from) or a single
/// source, preview a result, and add it. With one source selected, results
/// can be paged for more.
class MangaSourceSearch extends ConsumerStatefulWidget {
  final String query;
  const MangaSourceSearch({super.key, required this.query});

  @override
  ConsumerState<MangaSourceSearch> createState() => _MangaSourceSearchState();
}

class _MangaSourceSearchState extends ConsumerState<MangaSourceSearch> {
  SuwayomiBackend? _backend;
  List<({String id, String name, String lang})> _sources = const [];
  Set<String> _yours = {};
  String? _selected; // null = your sources
  List<_Hit> _hits = [];
  bool _loading = false;
  bool _hasNext = false;
  int _page = 1;
  String? _error;
  SourceListingCache? _listings;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(MangaSourceSearch old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _search(reset: true);
  }

  Future<void> _init() async {
    try {
      final backend = await ref.read(suwayomiBackendProvider.future);
      if (backend == null) {
        setState(() => _error = 'Searching sources needs a Suwayomi server.');
        return;
      }
      final all = await backend.listInstalledSources();
      final taste = await backend.libraryTaste();
      if (!mounted) return;
      setState(() {
        _backend = backend;
        // English/multi-language sources only: 100+ translated copies of one
        // site would bury the ones you use.
        _sources = all.where((s) => s.lang == 'en' || s.lang == 'all').toList();
        _yours = Recommender.topSources(taste, limit: 4).toSet();
      });
      _search(reset: true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  String _sourceName(String id) =>
      _sources.where((s) => s.id == id).map((s) => s.name).firstOrNull ?? 'Source';

  Future<void> _search({required bool reset}) async {
    final backend = _backend;
    final query = widget.query.trim();
    if (backend == null || query.isEmpty) {
      setState(() => _hits = []);
      return;
    }
    final ids = _selected != null ? [_selected!] : _yours.toList();
    if (reset) _page = 1;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) _hits = [];
    });
    try {
      final results = await Future.wait(ids.map((sid) async {
        try {
          final r = await backend.browseSource(sid, query: query, page: _page);
          return (
            hits: r.mangas
                .map((m) => _Hit(m.id, m.title, m.thumbnailUrl, sid))
                .toList(),
            next: r.hasNext,
          );
        } catch (_) {
          return (hits: <_Hit>[], next: false);
        }
      }));
      if (!mounted || query != widget.query.trim()) return;
      setState(() {
        _hits = [..._hits, for (final r in results) ...r.hits];
        // Paging only makes sense against one source at a time.
        _hasNext = ids.length == 1 && results.first.next;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pick(String? id) {
    if (id == _selected) return;
    setState(() => _selected = id);
    _search(reset: true);
  }

  /// Nothing typed yet: show what the sources have - a Popular/Latest shelf
  /// per source (the ones your library comes from first), or one source's
  /// full listing when its chip is picked.
  Widget _browse() {
    final backend = _backend;
    if (backend == null) return const Center(child: CircularProgressIndicator());
    final listings = _listings ??= SourceListingCache(backend);
    void open(SourceInfo s, SourceManga m) => showMangaPreview(
          context,
          ref,
          backend: backend,
          id: m.id,
          title: m.title,
          coverUrl: m.thumbnailUrl,
          sourceName: s.name,
        );

    final selected = _sources.where((s) => s.id == _selected).firstOrNull;
    if (selected != null) {
      return SourceCatalogGrid(
        key: ValueKey(selected.id),
        source: selected,
        cache: listings,
        onOpen: (m) => open(selected, m),
      );
    }
    return SourceShelves(
      sources: [
        ..._sources.where((s) => _yours.contains(s.id)),
        ..._sources.where((s) => !_yours.contains(s.id)),
      ],
      cache: listings,
      onOpen: open,
      onSeeAll: (s) => _pick(s.id),
    );
  }

  void _preview(_Hit hit) => showMangaPreview(
        context,
        ref,
        backend: _backend!,
        id: hit.id,
        title: hit.title,
        coverUrl: hit.thumbnailUrl,
        sourceName: _sourceName(hit.sourceId),
      );

  @override
  Widget build(BuildContext context) {
    if (_error != null && _backend == null) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(_error!,
            textAlign: TextAlign.center, style: AppText.body(color: AppColors.text60)),
      ));
    }
    return Column(
      children: [
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            children: [
              _SourceChip(
                  label: 'Your sources',
                  selected: _selected == null,
                  onTap: () => _pick(null)),
              for (final s in _sources) ...[
                const SizedBox(width: 7),
                _SourceChip(
                    label: s.name,
                    selected: _selected == s.id,
                    onTap: () => _pick(s.id)),
              ],
            ],
          ),
        ),
        Expanded(child: _results()),
      ],
    );
  }

  Widget _results() {
    if (widget.query.trim().isEmpty) return _browse();
    if (_hits.isEmpty) {
      return Center(
        child: _loading
            ? const CircularProgressIndicator()
            : Text('No matches on ${_selected == null ? "your sources" : _sourceName(_selected!)}.',
                style: AppText.body(color: AppColors.text45)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        for (final h in _hits)
          _HitRow(
            cover: h.thumbnailUrl,
            title: h.title,
            meta: _sourceName(h.sourceId).toUpperCase(),
            onTap: () => _preview(h),
          ),
        if (_hasNext)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: () {
                        _page++;
                        _search(reset: false);
                      },
                      child: const Text('Load more'),
                    ),
            ),
          ),
      ],
    );
  }
}

/// Opens the review sheet for a title on one of Suwayomi's sources: cover,
/// status/author, genres, description and chapter count, with Add to
/// library (then Open once added).
void showMangaPreview(
  BuildContext context,
  WidgetRef ref, {
  required SuwayomiBackend backend,
  required int id,
  required String title,
  required String coverUrl,
  required String sourceName,
}) {
  showAcquireSheet(
    context,
    coverUrl: coverUrl,
    title: title,
    subtitle: sourceName.toUpperCase(),
    details: _MangaDetails(backend: backend, id: id),
    actionLabel: 'Add to library',
    onAction: () => backend.addToLibraryWithCategories(id, const []),
    doneLabel: 'Open',
    onDone: () async {
      await activateServer(ref, backend.config.id);
      if (context.mounted) context.push('/series/$id');
    },
  );
}

/// The preview's body for a manga: author/status, genres, description and,
/// once the source answers, how many chapters it has.
class _MangaDetails extends StatefulWidget {
  final SuwayomiBackend backend;
  final int id;
  const _MangaDetails({required this.backend, required this.id});

  @override
  State<_MangaDetails> createState() => _MangaDetailsState();
}

class _MangaDetailsState extends State<_MangaDetails> {
  late final _preview = widget.backend.mangaPreview(widget.id);
  late final _chapters = widget.backend.chapterSummary(widget.id);

  String _status(String s) =>
      s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder(
          future: _preview,
          builder: (context, snap) {
            if (snap.hasError) {
              return Text("Couldn't load details from the source.",
                  style: AppText.body(size: 13, color: AppColors.dangerText));
            }
            final p = snap.data;
            if (p == null) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(minHeight: 2),
              );
            }
            final line = [
              if (p.status.isNotEmpty) _status(p.status),
              if (p.author.isNotEmpty) p.author,
            ].join('  ·  ');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (line.isNotEmpty)
                  Text(line, style: AppText.mono(size: 10.5, color: AppColors.text60)),
                if (p.genres.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final g in p.genres.take(8))
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.fillSubtle,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(g, style: AppText.body(size: 11, color: AppColors.text60)),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                _Expandable(p.description),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        FutureBuilder(
          future: _chapters,
          builder: (context, snap) {
            final c = snap.data;
            return Text(
              snap.hasError
                  ? 'Chapter list unavailable'
                  : c == null
                      ? 'Counting chapters...'
                      : '${c.count} chapters${c.latest == null ? '' : ', latest: ${c.latest}'}',
              style: AppText.mono(size: 10.5, color: AppColors.accentLink),
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Comics: search Kapowarr (ComicVine) and add a volume
// ---------------------------------------------------------------------------

/// Searches ComicVine through Kapowarr. Adding a volume makes Kapowarr start
/// acquiring its issues, which then land in your comics library.
class ComicSearch extends ConsumerStatefulWidget {
  final String query;
  const ComicSearch({super.key, required this.query});

  @override
  ConsumerState<ComicSearch> createState() => _ComicSearchState();
}

class _ComicSearchState extends ConsumerState<ComicSearch> {
  static const _pageSize = 20;

  List<KapowarrSearchResult> _results = [];
  int _visible = _pageSize;
  bool _loading = false;
  String? _error;
  KapowarrClient? _client;
  final _added = <int>{};

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void didUpdateWidget(ComicSearch old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _search();
  }

  Future<void> _search() async {
    final query = widget.query.trim();
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _visible = _pageSize;
    });
    try {
      final config = await ref.read(kapowarrConfigProvider.future);
      if (config == null) {
        if (mounted) setState(() => _client = null);
        return;
      }
      final client = _client = KapowarrClient(config: config);
      final results = await client.searchVolumes(query);
      if (mounted && query == widget.query.trim()) setState(() => _results = results);
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't search Kapowarr: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _preview(KapowarrSearchResult r) {
    final client = _client!;
    showAcquireSheet(
      context,
      coverUrl: r.coverUrl,
      title: r.title,
      subtitle: [
        if (r.publisher.isNotEmpty) r.publisher,
        if (r.year > 0) '${r.year}',
        '${r.issueCount} issues',
      ].join('  ·  ').toUpperCase(),
      details: _Expandable(r.description),
      actionLabel: 'Add to Kapowarr',
      alreadyHave: r.alreadyAdded || _added.contains(r.comicvineId),
      alreadyHaveLabel: 'Already in Kapowarr',
      onAction: () async {
        await client.addVolume(r.comicvineId);
        if (mounted) setState(() => _added.add(r.comicvineId));
      },
      doneLabel: 'View in Kapowarr',
      onDone: () => context.push('/settings/kapowarr/volumes'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(kapowarrConfigProvider);
    if (configAsync.valueOrNull == null && !configAsync.isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Connect Kapowarr to find and acquire comics.',
                  textAlign: TextAlign.center,
                  style: AppText.body(color: AppColors.text60)),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => context.push('/settings/kapowarr/edit'),
                child: const Text('Set up Kapowarr'),
              ),
            ],
          ),
        ),
      );
    }
    if (widget.query.trim().isEmpty) {
      return Center(
        child: Text('Search comics to acquire through Kapowarr.',
            style: AppText.body(color: AppColors.text45)),
      );
    }
    if (_error != null) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(_error!,
            textAlign: TextAlign.center, style: AppText.body(color: AppColors.dangerText)),
      ));
    }
    if (_loading && _results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text('Searching ComicVine...',
                style: AppText.body(size: 12.5, color: AppColors.text45)),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text('No comics found.', style: AppText.body(color: AppColors.text45)),
      );
    }
    final shown = _results.take(_visible).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        for (final r in shown)
          _HitRow(
            cover: r.coverUrl,
            title: r.year > 0 ? '${r.title} (${r.year})' : r.title,
            meta: [
              if (r.publisher.isNotEmpty) r.publisher,
              '${r.issueCount} issues',
              if (r.alreadyAdded || _added.contains(r.comicvineId)) 'in kapowarr',
            ].join('  ·  ').toUpperCase(),
            onTap: () => _preview(r),
          ),
        if (_visible < _results.length)
          Center(
            child: TextButton(
              onPressed: () => setState(() => _visible += _pageSize),
              child: Text('Show more (${_results.length - _visible} left)'),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _SourceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SourceChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.scaled(context, Motion.fast),
          curve: Motion.easeOut,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent.withValues(alpha: 0.16) : AppColors.fillSubtle,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? AppColors.accent : Colors.transparent),
          ),
          child: Text(
            label,
            style: AppText.body(
              size: 11.5,
              weight: FontWeight.w600,
              color: selected ? AppColors.accentLink : AppColors.text60,
            ),
          ),
        ),
      ),
    );
  }
}

class _HitRow extends StatelessWidget {
  final String cover;
  final String title;
  final String meta;
  final VoidCallback onTap;
  const _HitRow(
      {required this.cover, required this.title, required this.meta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      scale: 0.985,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              SizedBox(
                width: 46,
                height: 66,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SeriesCover(imageUrl: cover),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(size: 14.5, weight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.mono(size: 10)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.text30),
            ],
          ),
        ),
      ),
    );
  }
}
