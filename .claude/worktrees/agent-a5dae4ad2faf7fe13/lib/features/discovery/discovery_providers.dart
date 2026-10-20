import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../backends/suwayomi/suwayomi_backend.dart';
import '../../core/discovery/discovery_cache.dart';
import '../../core/discovery/recommender.dart';

/// The Suwayomi server to discover from (recommendations are Suwayomi-only:
/// it is the one that can browse and add titles from online sources).
final suwayomiBackendProvider = FutureProvider<SuwayomiBackend?>((ref) async {
  final all = await ref.watch(allBackendsProvider.future);
  return all.whereType<SuwayomiBackend>().firstOrNull;
});

/// Recommendations for Home's shelf. Served from the cache when it's under a
/// day old. Otherwise they're rebuilt here - a fresh install or a new device
/// has no cache, and waiting for someone to open the Recommended screen
/// meant the shelf just never appeared. A day-old cache is shown right away
/// while the rebuild runs, then swapped for the fresh set.
final cachedRecommendationsProvider = FutureProvider<List<Recommendation>>((ref) async {
  final cached = await DiscoveryCache().load();
  if (cached != null &&
      DateTime.now().toUtc().difference(cached.at) < const Duration(days: 1)) {
    return cached.items;
  }
  final backend = await ref.watch(suwayomiBackendProvider.future);
  if (backend == null) return cached?.items ?? const [];
  if (cached != null) {
    unawaited(computeRecommendations(backend)
        .then((_) => ref.invalidateSelf())
        .catchError((_) {}));
    return cached.items;
  }
  try {
    return await computeRecommendations(backend);
  } catch (_) {
    return const [];
  }
});

/// Builds fresh recommendations: read the library's taste, pull popular
/// titles from the sources it mostly comes from, rank them, and save the
/// result for Home.
Future<List<Recommendation>> computeRecommendations(SuwayomiBackend backend) async {
  final taste = await backend.libraryTaste();
  if (taste.isEmpty) return const [];
  final candidates =
      await backend.discoverCandidates(Recommender.topSources(taste, limit: 4));
  final recs = Recommender.rank(taste, candidates);
  await DiscoveryCache().save(recs);
  return recs;
}
