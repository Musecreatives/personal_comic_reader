import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../backends/suwayomi/suwayomi_backend.dart';
import '../../core/discovery/discovery_cache.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
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
                    onPressed: _busy ? null : () => _load(force: true),
                    icon: Icon(Icons.refresh_rounded, color: AppColors.text60),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Popular on the sources you read from, matched to the genres in your library.',
                style: AppText.body(size: 12.5, color: AppColors.text60),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: Motion.scaled(context, Motion.base),
                child: _body(backend, recs),
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
            rec: r,
            adding: _adding.contains(c.id),
            added: _added.contains(c.id),
            onAdd: backend == null ? null : () => _add(backend, c),
          ),
        );
      },
    );
  }
}

class _RecTile extends StatelessWidget {
  final Recommendation rec;
  final bool adding;
  final bool added;
  final VoidCallback? onAdd;
  const _RecTile({
    required this.rec,
    required this.adding,
    required this.added,
    required this.onAdd,
  });

  String _cap(String g) => g.isEmpty ? g : g[0].toUpperCase() + g.substring(1);

  @override
  Widget build(BuildContext context) {
    final c = rec.candidate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Stack(
              fit: StackFit.expand,
              children: [
                SeriesCover(imageUrl: c.thumbnailUrl),
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
        Text(c.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(size: 12, weight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(rec.because.map(_cap).join(', '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.mono(size: 9.5, color: AppColors.accentLink)),
      ],
    );
  }
}
