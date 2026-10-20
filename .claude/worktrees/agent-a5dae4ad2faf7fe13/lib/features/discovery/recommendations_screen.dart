import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../backends/suwayomi/suwayomi_backend.dart';
import '../../core/discovery/comic_recommender.dart';
import '../../core/discovery/discovery_cache.dart';
import '../../core/kapowarr/kapowarr_client.dart';
import '../../core/discovery/recommender.dart';
import '../shared/back_button.dart';
import '../shared/series_cover.dart';
import 'discovery_providers.dart';

/// Titles from your sources that match what your library is made of, with the
/// genres that made them match. Results are cached; the first visit (and
/// Refresh) does the slow part.
class RecommendationsScreen extends ConsumerStatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  ConsumerState<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends ConsumerState<RecommendationsScreen> {
  List<Recommendation>? _recs;
  bool _busy = true;
  String? _error;
  final _adding = <int>{};
  final _added = <int>{};

  late final bool _hasKapowarr = ref.read(kapowarrConfigStoreProvider).hasConfig;
  var _comicsMode = false;
  List<ComicRec>? _comics;
  bool _comicsBusy = false;
  String? _comicsError;
  KapowarrClient? _kapowarr;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _loadComics({bool force = false}) async {
    setState(() {
      _comicsBusy = true;
      _comicsError = null;
    });
    try {
      final config = await ref.read(kapowarrConfigStoreProvider).getWithApiKey();
      if (config == null) {
        setState(() => _comicsError = 'Comic recommendations need Kapowarr.');
        return;
      }
      final client = _kapowarr = KapowarrClient(config: config);
      if (!force) {
        final cached = await ComicRecCache.load();
        if (cached != null) {
          if (mounted) setState(() => _comics = cached);
          return;
        }
      }
      final recs = await computeComicRecommendations(client);
      if (mounted) setState(() => _comics = recs);
    } catch (e) {
      if (mounted) setState(() => _comicsError = '$e');
    } finally {
      if (mounted) setState(() => _comicsBusy = false);
    }
  }

  Future<void> _addComic(ComicRec r) async {
    final client = _kapowarr;
    if (client == null) return;
    final id = r.volume.comicvineId;
    setState(() => _adding.add(id));
    try {
      await client.addVolume(id);
      if (mounted) setState(() => _added.add(id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Couldn't add it to Kapowarr: $e")));
      }
    } finally {
      if (mounted) setState(() => _adding.remove(id));
    }
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final backend = await ref.read(suwayomiBackendProvider.future);
      if (backend == null) {
        setState(() => _error = 'Recommendations need a Suwayomi server.');
        return;
      }
      if (!force) {
        final cached = await DiscoveryCache().load();
        if (cached != null) {
          if (mounted) setState(() => _recs = cached.items);
          return;
        }
      }
      final recs = await computeRecommendations(backend);
      ref.invalidate(cachedRecommendationsProvider);
      if (mounted) setState(() => _recs = recs);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(SuwayomiBackend backend, Candidate c) async {
    setState(() => _adding.add(c.id));
    try {
      await backend.addToLibraryWithCategories(c.id, const []);
      if (mounted) setState(() => _added.add(c.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Couldn't add it: $e")));
      }
    } finally {
      if (mounted) setState(() => _adding.remove(c.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(suwayomiBackendProvider).valueOrNull;
    final recs = _recs;

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
              child: Row(
                children: [
                  const AppBackButton(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Recommended', style: AppText.largeTitle(size: 24)),
                  ),
                  IconButton(
                    tooltip: 'Find new recommendations',
                    onPressed: _comicsMode
                        ? (_comicsBusy ? null : () => _loadComics(force: true))
                        : (_busy ? null : () => _load(force: true)),
                    icon: Icon(Icons.refresh_rounded, color: AppColors.text60),
                  ),
                ],
              ),
            ),
            if (_hasKapowarr)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Manga')),
                    ButtonSegment(value: true, label: Text('Comics')),
                  ],
                  selected: {_comicsMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    setState(() => _comicsMode = s.first);
                    if (_comicsMode && _comics == null && !_comicsBusy) _loadComics();
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                _comicsMode
                    ? 'Recent runs of the characters and series in your Kapowarr library.'
                    : 'Popular on the sources you read from, matched to the genres in your library.',
                style: AppText.body(size: 12.5, color: AppColors.text60),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: Motion.scaled(context, Motion.base),
                child: _comicsMode ? _comicsBody() : _body(backend, recs),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(SuwayomiBackend? backend, List<Recommendation>? recs) {
    if (_error != null && recs == null) {
      return Center(
        key: const ValueKey('error'),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: AppText.body(color: AppColors.text60)),
        ),
      );
    }
    if (recs == null) {
      return Center(
        key: const ValueKey('busy'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text('Finding titles that match your library',
                style: AppText.body(size: 13, color: AppColors.text60)),
            const SizedBox(height: 4),
            Text('This takes a little while the first time',
                style: AppText.body(size: 11.5, color: AppColors.text45)),
          ],
        ),
      );
    }
    if (recs.isEmpty) {
      return Center(
        key: const ValueKey('empty'),
        child: Text('Nothing new matches your library right now.',
            style: AppText.body(color: AppColors.text60)),
      );
    }
    return GridView.builder(
      key: const ValueKey('grid'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        mainAxisSpacing: 16,
        crossAxisSpacing: 13,
        childAspectRatio: 0.46,
      ),
      itemCount: recs.length,
      itemBuilder: (context, i) {
        final r = recs[i];
        final c = r.candidate;
        return FadeSlideIn(
          delay: Duration(milliseconds: 30 * math.min(i, 8)),
          child: _RecTile(
            title: c.title,
            imageUrl: c.thumbnailUrl,
            caption: r.because.map(_cap).join(', '),
            adding: _adding.contains(c.id),
            added: _added.contains(c.id),
            onAdd: backend == null ? null : () => _add(backend, c),
          ),
        );
      },
    );
  }

  static String _cap(String g) => g.isEmpty ? g : g[0].toUpperCase() + g.substring(1);

  Widget _comicsBody() {
    final comics = _comics;
    if (_comicsError != null && comics == null) {
      return Center(
        key: const ValueKey('comics-error'),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(_comicsError!,
              textAlign: TextAlign.center,
              style: AppText.body(color: AppColors.text60)),
        ),
      );
    }
    if (comics == null) {
      return Center(
        key: const ValueKey('comics-busy'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text('Searching ComicVine for your characters and series',
                style: AppText.body(size: 13, color: AppColors.text60)),
            const SizedBox(height: 4),
            Text('This can take a minute the first time',
                style: AppText.body(size: 11.5, color: AppColors.text45)),
          ],
        ),
      );
    }
    if (comics.isEmpty) {
      return Center(
        key: const ValueKey('comics-empty'),
        child: Text('Nothing new matches your comics right now.',
            style: AppText.body(color: AppColors.text60)),
      );
    }
    return GridView.builder(
      key: const ValueKey('comics-grid'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        mainAxisSpacing: 16,
        crossAxisSpacing: 13,
        childAspectRatio: 0.46,
      ),
      itemCount: comics.length,
      itemBuilder: (context, i) {
        final r = comics[i];
        final v = r.volume;
        return FadeSlideIn(
          delay: Duration(milliseconds: 30 * math.min(i, 8)),
          child: _RecTile(
            title: v.year > 0 ? '${v.title} (${v.year})' : v.title,
            imageUrl: v.coverUrl.isEmpty ? null : v.coverUrl,
            caption: 'Because of ${_cap(r.because)}',
            adding: _adding.contains(v.comicvineId),
            added: _added.contains(v.comicvineId),
            onAdd: () => _addComic(r),
          ),
        );
      },
    );
  }
}

class _RecTile extends StatelessWidget {
  final String title;
  final String? imageUrl;
  final String caption;
  final bool adding;
  final bool added;
  final VoidCallback? onAdd;
  const _RecTile({
    required this.title,
    required this.imageUrl,
    required this.caption,
    required this.adding,
    required this.added,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Stack(
              fit: StackFit.expand,
              children: [
                SeriesCover(imageUrl: imageUrl),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: PressScale(
                    scale: 0.92,
                    child: GestureDetector(
                      onTap: added || adding ? null : onAdd,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: added ? AppColors.suwayomi : AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: adding
                            ? const Padding(
                                padding: EdgeInsets.all(9),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(added ? Icons.check_rounded : Icons.add_rounded,
                                size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(size: 12, weight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.mono(size: 9.5, color: AppColors.accentLink)),
      ],
    );
  }
}
