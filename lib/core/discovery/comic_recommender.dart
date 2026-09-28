import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../kapowarr/kapowarr_client.dart';

/// A ComicVine volume worth suggesting, and the library title that led to it.
class ComicRec {
  final KapowarrSearchResult volume;
  final String because;
  const ComicRec(this.volume, this.because);
}

/// Comic recommendations built from what Kapowarr already tracks. ComicVine
/// (through Kapowarr) only offers text search - no "popular" or "similar"
/// lists - so the library's recurring characters/franchises become search
/// terms, and the results are ranked toward recent runs from the publishers
/// you already read.
class ComicRecommender {
  /// Words that dress a title up rather than name what it's about:
  /// "Absolute Wonder Woman" and "Wonder Woman" are the same interest.
  static const _prefixes = {
    'the', 'a', 'an', 'absolute', 'ultimate', 'ultimates', 'all', 'new',
    'all-new', 'amazing', 'astonishing', 'uncanny', 'spectacular',
    'sensational', 'superior', 'immortal', 'mighty', 'incredible', 'savage',
    'dc', 'marvel', 'dark', 'young',
  };

  /// The core of a title: leading qualifiers, years, issue/volume numbers and
  /// subtitles removed. "The Amazing Spider-Man (2022)" -> "spider-man".
  static String core(String title) {
    final t = title
        .toLowerCase()
        .replaceAll(RegExp(r'\(.*?\)'), ' ')
        .split(RegExp(r'[:–—]| - '))
        .first
        .replaceAll(RegExp(r'\b(vol(ume)?\.?\s*)?\d+\b'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\- ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final words = t.split(' ');
    while (words.length > 1 && _prefixes.contains(words.first)) {
      words.removeAt(0);
    }
    return words.join(' ');
  }

  /// What to search ComicVine for: the library's most repeated title cores,
  /// newest first among ties, up to [limit].
  static List<String> searchTerms(List<KapowarrVolume> library, {int limit = 5}) {
    final counts = <String, int>{};
    final newest = <String, int>{};
    for (final v in library) {
      final c = core(v.title);
      if (c.length < 3) continue;
      counts[c] = (counts[c] ?? 0) + 1;
      if (v.year > (newest[c] ?? 0)) newest[c] = v.year;
    }
    final terms = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : newest[b]!.compareTo(newest[a]!);
      });
    return terms.take(limit).toList();
  }

  /// [results] maps each search term to what ComicVine returned for it.
  /// Drops anything already in Kapowarr or the library, empty volumes and
  /// duplicates; ranks recent volumes from familiar publishers first.
  static List<ComicRec> rank(
    List<KapowarrVolume> library,
    Map<String, List<KapowarrSearchResult>> results, {
    int limit = 24,
    int? currentYear,
  }) {
    final year = currentYear ?? DateTime.now().year;
    final publishers = <String, int>{};
    for (final v in library) {
      if (v.publisher.isNotEmpty) {
        publishers[v.publisher] = (publishers[v.publisher] ?? 0) + 1;
      }
    }
    final owned = {for (final v in library) '${v.title.toLowerCase()}|${v.year}'};

    final scored = <int, (ComicRec, double)>{};
    for (final MapEntry(key: term, value: hits) in results.entries) {
      for (final r in hits) {
        if (r.alreadyAdded || r.issueCount == 0) continue;
        if (owned.contains('${r.title.toLowerCase()}|${r.year}')) continue;
        final familiar = library.isEmpty
            ? 0.5
            : (publishers[r.publisher] ?? 0) / library.length;
        final age = (year - r.year).clamp(0, 50);
        final recency = r.year == 0 ? 0.0 : 1 / (1 + age / 2);
        // Recency leads: a 1940 run from a familiar publisher shouldn't beat
        // last year's from a new one.
        final score = recency * 3 + familiar * 0.5;
        final prev = scored[r.comicvineId];
        if (prev == null || score > prev.$2) {
          scored[r.comicvineId] = (ComicRec(r, term), score);
        }
      }
    }
    final ranked = scored.values.toList()..sort((a, b) => b.$2.compareTo(a.$2));
    return ranked.take(limit).map((e) => e.$1).toList();
  }
}

/// Searches for each term (in parallel), ranks, and caches the result. A
/// failing search is skipped rather than failing the lot.
Future<List<ComicRec>> computeComicRecommendations(KapowarrClient client) async {
  final library = await client.getVolumes();
  if (library.isEmpty) return const [];
  final terms = ComicRecommender.searchTerms(library);
  final results = <String, List<KapowarrSearchResult>>{};
  await Future.wait(terms.map((t) async {
    try {
      results[t] = await client.searchVolumes(t);
    } catch (_) {}
  }));
  final recs = ComicRecommender.rank(library, results);
  await ComicRecCache.save(recs);
  return recs;
}

/// Same idea as DiscoveryCache: searching ComicVine is slow, so the last set
/// is kept for instant display.
class ComicRecCache {
  static const _boxName = 'recommendations';
  static const _key = 'comics';

  static Future<void> save(List<ComicRec> recs) async {
    final box = await Hive.openBox<String>(_boxName);
    await box.put(
      _key,
      jsonEncode({
        'at': DateTime.now().toUtc().toIso8601String(),
        'items': [
          for (final r in recs) {'because': r.because, 'volume': _toJson(r.volume)},
        ],
      }),
    );
  }

  static Future<List<ComicRec>?> load({Duration maxAge = const Duration(days: 7)}) async {
    final raw = (await Hive.openBox<String>(_boxName)).get(_key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (DateTime.now().toUtc().difference(DateTime.parse(json['at'] as String)) > maxAge) {
        return null;
      }
      return [
        for (final e in json['items'] as List)
          ComicRec(
            KapowarrSearchResult.fromJson(e['volume'] as Map<String, dynamic>),
            e['because'] as String,
          ),
      ];
    } catch (_) {
      return null;
    }
  }

  // The API's own field names, so KapowarrSearchResult.fromJson reads it back.
  static Map<String, dynamic> _toJson(KapowarrSearchResult r) => {
        'comicvine_id': r.comicvineId,
        'title': r.title,
        'year': r.year,
        'volume_number': r.volumeNumber,
        'cover_link': r.coverUrl,
        'description': r.description,
        'publisher': r.publisher,
        'issue_count': r.issueCount,
        'already_added': r.alreadyAdded,
      };
}
