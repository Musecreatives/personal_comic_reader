import 'dart:math' as math;

/// A title already in the library, reduced to what taste is built from.
class TasteTitle {
  final String title;
  final List<String> genres;
  final String sourceId;
  const TasteTitle({required this.title, required this.genres, required this.sourceId});
}

/// Something a source offers that is not in the library (yet).
class Candidate {
  final int id;
  final String title;
  final String thumbnailUrl;
  final List<String> genres;
  final String sourceId;
  const Candidate({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    required this.genres,
    required this.sourceId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'thumbnailUrl': thumbnailUrl,
        'genres': genres,
        'sourceId': sourceId,
      };

  factory Candidate.fromJson(Map<String, dynamic> j) => Candidate(
        id: j['id'] as int,
        title: j['title'] as String,
        thumbnailUrl: j['thumbnailUrl'] as String,
        genres: (j['genres'] as List).cast<String>(),
        sourceId: j['sourceId'] as String,
      );
}

class Recommendation {
  final Candidate candidate;
  final double score;

  /// The shared genres that mattered most, for "Because you read ...".
  final List<String> because;
  const Recommendation(this.candidate, this.score, this.because);
}

/// Ranks candidates by how well their genres match what the library is made
/// of. A genre nearly every title has ("Action" at 85%) says little about
/// taste, while one held by a minority ("Martial arts" at 24%) says a lot, so
/// a genre's weight is `share * (1 - share)`: highest for mid-frequency
/// genres, low for both ubiquitous and one-off ones.
class Recommender {
  static String _genre(String g) => g.trim().toLowerCase();

  /// Comparison key so "The Beginning After the End!" and "the beginning
  /// after the end" count as the same title.
  static String normalizeTitle(String t) =>
      t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  static Map<String, double> genreWeights(List<TasteTitle> library) {
    if (library.isEmpty) return const {};
    final counts = <String, int>{};
    for (final t in library) {
      for (final g in t.genres.map(_genre).toSet()) {
        counts[g] = (counts[g] ?? 0) + 1;
      }
    }
    final n = library.length;
    return {
      for (final e in counts.entries)
        e.key: (e.value / n) * (1 - e.value / n),
    };
  }

  /// The sources the library actually comes from, most-used first.
  static List<String> topSources(List<TasteTitle> library, {int limit = 4}) {
    final counts = <String, int>{};
    for (final t in library) {
      counts[t.sourceId] = (counts[t.sourceId] ?? 0) + 1;
    }
    final ordered = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return ordered.take(limit).toList();
  }

  static List<Recommendation> rank(
    List<TasteTitle> library,
    List<Candidate> candidates, {
    int limit = 24,
  }) {
    final weights = genreWeights(library);
    final owned = library.map((t) => normalizeTitle(t.title)).toSet();

    final best = <String, Recommendation>{};
    for (final c in candidates) {
      final key = normalizeTitle(c.title);
      if (key.isEmpty || owned.contains(key)) continue;

      final shared = <String, double>{};
      for (final g in c.genres.map(_genre).toSet()) {
        final w = weights[g];
        if (w != null && w > 0) shared[g] = w;
      }
      if (shared.isEmpty) continue;

      // Sum of matched weights, softened for candidates with very long tag
      // lists so they don't win just by carrying more tags.
      final raw = shared.values.fold<double>(0, (a, b) => a + b);
      final score = raw / math.sqrt(math.max(1, c.genres.length));
      final because = (shared.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(2)
          .map((e) => e.key)
          .toList();

      final current = best[key];
      if (current == null || score > current.score) {
        best[key] = Recommendation(c, score, because);
      }
    }
    final ranked = best.values.toList()..sort((a, b) => b.score.compareTo(a.score));
    return ranked.take(limit).toList();
  }
}
