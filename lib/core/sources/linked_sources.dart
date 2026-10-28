import 'dart:convert';

/// Suwayomi manga meta key holding a series' backup sources: a JSON list of
/// manga ids on other extensions. Stored on the server, so every app user
/// shares the same links.
const linkedSourcesMetaKey = 'shaddai.linkedSources';

/// The linked manga ids in [raw] (the meta value). Anything unreadable is
/// treated as no links rather than an error.
List<int> parseLinkedIds(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final v in decoded)
        if (v is int) v else if (v is String && int.tryParse(v) != null) int.parse(v),
    ];
  } on FormatException {
    return const [];
  }
}

/// The chapter id in [byNumber] for chapter [number] (a Book.number such as
/// "161", "10.5" or "161.0"). Null when the number is unknown: Suwayomi uses
/// -1 for chapters it couldn't number, which must never match each other.
int? matchChapterId(Map<double, int> byNumber, String number) {
  final n = double.tryParse(number);
  if (n == null || n < 0) return null;
  return byNumber[n];
}

/// Walks [linkedIds] in order and returns the first source that has chapter
/// [number]. A source that fails to answer is skipped, not fatal: the point
/// is to find any copy that loads.
Future<({int mangaId, int chapterId})?> findFallbackChapter(
  List<int> linkedIds,
  String number,
  Future<Map<double, int>> Function(int mangaId) chaptersOf,
) async {
  for (final id in linkedIds) {
    try {
      final chapterId = matchChapterId(await chaptersOf(id), number);
      if (chapterId != null) return (mangaId: id, chapterId: chapterId);
    } catch (_) {
      // That source is down too; try the next one.
    }
  }
  return null;
}

/// Progress on a backup chapter, moved onto the main chapter. Page counts
/// differ between sources, so the position is carried as a fraction; the
/// last page always maps to the last page so "finished" survives.
int mapFallbackPage(int page, int servedCount, int mainCount) {
  if (mainCount <= 0 || servedCount <= 0) return page;
  if (page >= servedCount - 1) return mainCount - 1;
  return ((page + 1) / servedCount * mainCount).round().clamp(1, mainCount) - 1;
}

// ---------------------------------------------------------------------------
// Ranking copies of one title. Translation quality can't be measured, so the
// owner marks it; the rest comes from the chapter lists the server already
// stores. A copy that meets at least two of these is worth putting first.
// ---------------------------------------------------------------------------

/// Manga meta key on the main series: the copies (manga ids) the owner marked
/// as having a good translation.
const goodTranslationMetaKey = 'shaddai.goodTranslation';

enum SourceStrength {
  upToDate('UP TO DATE'),
  onTime('ON TIME'),
  consistent('FEWEST GAPS'),
  goodTranslation('GOOD TRANSLATION');

  const SourceStrength(this.label);
  final String label;
}

/// What one copy's stored chapter list says about it.
class CopyStats {
  final double newestNumber;
  final DateTime? newestUpload;

  /// Whole chapter numbers missing between 1 and [newestNumber].
  final int gaps;
  final bool goodTranslation;

  const CopyStats({
    required this.newestNumber,
    required this.newestUpload,
    required this.gaps,
    this.goodTranslation = false,
  });

  /// From (chapter number, upload time in ms) pairs. Unnumbered chapters
  /// (-1) and part chapters (10.5) don't count towards gaps.
  factory CopyStats.fromChapters(Iterable<(double, int)> chapters, {bool goodTranslation = false}) {
    var newest = 0.0;
    var uploadMs = 0;
    final whole = <int>{};
    for (final (n, up) in chapters) {
      if (n > newest) newest = n;
      if (up > uploadMs) uploadMs = up;
      if (n >= 1 && n == n.roundToDouble()) whole.add(n.toInt());
    }
    final top = newest.floor();
    return CopyStats(
      newestNumber: newest,
      newestUpload: uploadMs == 0 ? null : DateTime.fromMillisecondsSinceEpoch(uploadMs),
      gaps: top < 1 ? 0 : top - whole.where((n) => n <= top).length,
      goodTranslation: goodTranslation,
    );
  }
}

/// Which strengths each of [copies] has, compared with the others. "On
/// time" allows two days, since sites post the same chapter hours apart.
List<Set<SourceStrength>> sourceStrengths(List<CopyStats> copies) {
  if (copies.isEmpty) return const [];
  final bestNumber = copies.map((c) => c.newestNumber).reduce((a, b) => a > b ? a : b);
  final uploads = copies.map((c) => c.newestUpload).nonNulls;
  final bestUpload = uploads.isEmpty ? null : uploads.reduce((a, b) => a.isAfter(b) ? a : b);
  final fewestGaps = copies.map((c) => c.gaps).reduce((a, b) => a < b ? a : b);
  return [
    for (final c in copies)
      {
        if (bestNumber > 0 && c.newestNumber >= bestNumber) SourceStrength.upToDate,
        if (bestUpload != null &&
            c.newestUpload != null &&
            bestUpload.difference(c.newestUpload!) <= const Duration(days: 2))
          SourceStrength.onTime,
        if (bestNumber > 0 && c.gaps == fewestGaps) SourceStrength.consistent,
        if (c.goodTranslation) SourceStrength.goodTranslation,
      },
  ];
}

/// [ids] reordered by how many strengths each has, most first; ties keep
/// their current (manual) order.
List<int> rankByStrength(List<int> ids, List<Set<SourceStrength>> strengths) {
  final order = [for (var i = 0; i < ids.length; i++) i]
    ..sort((a, b) {
      final byScore = strengths[b].length.compareTo(strengths[a].length);
      return byScore != 0 ? byScore : a.compareTo(b);
    });
  return [for (final i in order) ids[i]];
}
