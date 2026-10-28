import '../backend/models.dart';

/// One new chapter from one server, before grouping.
class UpdateChapter {
  final String serverId;
  final String seriesTitle;
  final Book book;
  const UpdateChapter({required this.serverId, required this.seriesTitle, required this.book});
}

/// The new chapters of one series that arrived on one day: shown as a
/// single row ("Ch. 160–162"), so a series that got its whole back
/// catalogue fetched at once is one line, not two hundred.
class UpdateGroup {
  final String serverId;
  final String seriesId;
  final String seriesTitle;
  final DateTime day;

  /// Newest first.
  final List<Book> chapters;

  const UpdateGroup({
    required this.serverId,
    required this.seriesId,
    required this.seriesTitle,
    required this.day,
    required this.chapters,
  });

  DateTime get latestAt => chapters.first.addedAt!;
  bool get hasUnread => chapters.any((c) => !c.completed);

  /// The chapter a tap opens: the oldest unread one, so reading goes in
  /// order; the newest when all are read.
  Book get next => chapters.lastWhere((c) => !c.completed, orElse: () => chapters.first);
}

DateTime _dayOf(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// [chapters] from every server, kept to series [follows] says you are
/// reading or have finished, newest first, one group per series per day.
/// Chapters without a date can't be placed and are left out.
List<UpdateGroup> groupUpdates(
  Iterable<UpdateChapter> chapters, {
  required bool Function(String serverId, String seriesId) follows,
}) {
  final sorted = chapters
      .where((c) => c.book.addedAt != null && follows(c.serverId, c.book.seriesId))
      .toList()
    ..sort((a, b) => b.book.addedAt!.compareTo(a.book.addedAt!));
  final groups = <String, (UpdateChapter, List<Book>)>{};
  for (final c in sorted) {
    final key = '${c.serverId}|${c.book.seriesId}|${_dayOf(c.book.addedAt!)}';
    groups.putIfAbsent(key, () => (c, <Book>[])).$2.add(c.book);
  }
  return [
    for (final (first, books) in groups.values)
      UpdateGroup(
        serverId: first.serverId,
        seriesId: first.book.seriesId,
        seriesTitle: first.seriesTitle,
        day: _dayOf(first.book.addedAt!),
        chapters: books,
      ),
  ];
}

/// "TODAY", "YESTERDAY", then "MON 26 OCT" (the year only when it isn't
/// this one).
String dayLabel(DateTime day, DateTime now) {
  final today = _dayOf(now);
  final d = _dayOf(day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'TODAY';
  if (diff == 1) return 'YESTERDAY';
  const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  final base = '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  return d.year == today.year ? base : '$base ${d.year}';
}

/// "CH. 162", or "CH. 160–162" for several (lowest to highest number).
String chapterRange(List<Book> chapters) {
  String fmt(String n) {
    final v = double.tryParse(n);
    if (v == null) return n;
    return v == v.roundToDouble() ? '${v.round()}' : '$v';
  }

  final nums = [for (final c in chapters) (double.tryParse(c.number), c.number)]
    ..sort((a, b) => (a.$1 ?? 0).compareTo(b.$1 ?? 0));
  if (nums.length == 1) return 'CH. ${fmt(nums.first.$2)}';
  return 'CH. ${fmt(nums.first.$2)}–${fmt(nums.last.$2)}';
}

/// "JUST NOW", "5 MIN AGO", "3 H AGO", "2 D AGO".
String agoLabel(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'JUST NOW';
  if (d.inMinutes < 60) return '${d.inMinutes} MIN AGO';
  if (d.inHours < 24) return '${d.inHours} H AGO';
  return '${d.inDays} D AGO';
}
