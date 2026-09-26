import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'recommender.dart';

/// The last set of recommendations, kept so Home can show them instantly and
/// without touching the network. Computing them is slow (it asks sources for
/// popular titles and looks up each one's genres), so only the Recommended
/// screen does that, and it saves the result here.
class DiscoveryCache {
  static const _boxName = 'recommendations';
  static const _key = 'latest';

  Future<Box<String>> _open() => Hive.openBox<String>(_boxName);

  Future<void> save(List<Recommendation> recs) async {
    final box = await _open();
    await box.put(
      _key,
      jsonEncode({
        'at': DateTime.now().toUtc().toIso8601String(),
        'items': [
          for (final r in recs)
            {'candidate': r.candidate.toJson(), 'score': r.score, 'because': r.because},
        ],
      }),
    );
  }

  /// The saved recommendations and when they were made, or null if there are
  /// none or they are older than [maxAge].
  Future<({List<Recommendation> items, DateTime at})?> load(
      {Duration maxAge = const Duration(days: 14)}) async {
    final raw = (await _open()).get(_key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final at = DateTime.parse(json['at'] as String);
      if (DateTime.now().toUtc().difference(at) > maxAge) return null;
      final items = (json['items'] as List)
          .map((e) => Recommendation(
                Candidate.fromJson(e['candidate'] as Map<String, dynamic>),
                (e['score'] as num).toDouble(),
                (e['because'] as List).cast<String>(),
              ))
          .toList();
      return (items: items, at: at);
    } catch (_) {
      return null; // a corrupt cache is just a miss
    }
  }

  Future<void> clear() async => (await _open()).delete(_key);
}
