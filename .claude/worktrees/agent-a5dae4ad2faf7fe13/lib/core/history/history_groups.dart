import '../backend/models.dart';
import 'history_entry.dart';

/// Everything read from one series (on one server), newest session first.
class HistorySeriesGroup {
  final String? serverId;
  final String seriesId;
  final List<HistoryEntry> entries;

  const HistorySeriesGroup({
    required this.serverId,
    required this.seriesId,
    required this.entries,
  });

  /// Series ids are only unique within a server.
  String get key => '${serverId ?? ''}|$seriesId';
  DateTime get lastRead => entries.first.timestamp;
}

/// Groups [entries] by series, most recently read series first. Each group's
/// chapters keep newest-first order. Input order doesn't matter.
List<HistorySeriesGroup> groupHistoryBySeries(List<HistoryEntry> entries) {
  final sorted = [...entries]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  final groups = <String, List<HistoryEntry>>{};
  for (final e in sorted) {
    groups.putIfAbsent('${e.serverId ?? ''}|${e.seriesId}', () => []).add(e);
  }
  return [
    for (final list in groups.values)
      HistorySeriesGroup(
        serverId: list.first.serverId,
        seriesId: list.first.seriesId,
        entries: list,
      ),
  ];
}

/// Chapters that came out after the furthest one read. [books] is the
/// series' chapter list in reading order; "furthest read" is the latest
/// position that's either in [readBookIds] (this device's history) or
/// marked read on the server. Anything after it that isn't read counts -
/// so going back to re-read an early chapter doesn't flag the rest as new.
List<Book> newChaptersSince(List<Book> books, Iterable<String> readBookIds) {
  final read = readBookIds.toSet();
  var furthest = -1;
  for (var i = 0; i < books.length; i++) {
    if (read.contains(books[i].id) || books[i].completed) furthest = i;
  }
  if (furthest < 0) return const [];
  return [
    for (final b in books.skip(furthest + 1))
      if (!b.completed) b,
  ];
}
