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

/// What was recommended last time, straight from the cache (no network).
/// Home uses this; the Recommended screen refreshes it.
final cachedRecommendationsProvider = FutureProvider<List<Recommendation>>((ref) async {
  final cached = await DiscoveryCache().load();
  return cached?.items ?? const [];
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
