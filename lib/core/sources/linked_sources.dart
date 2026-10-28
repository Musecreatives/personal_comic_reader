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
