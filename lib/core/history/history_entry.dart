/// One reading session recorded locally (6e History). Written when a
/// reader session ends (dispose), upserted per book so reopening the same
/// chapter updates its existing row instead of duplicating it.
class HistoryEntry {
  final String bookId;
  final String seriesId;
  final String bookTitle;
  final String bookNumber;
  final int pageCount;
  final int lastPage;
  final bool completed;
  final DateTime timestamp;

  const HistoryEntry({
    required this.bookId,
    required this.seriesId,
    required this.bookTitle,
    required this.bookNumber,
    required this.pageCount,
    required this.lastPage,
    required this.completed,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'bookId': bookId,
        'seriesId': seriesId,
        'bookTitle': bookTitle,
        'bookNumber': bookNumber,
        'pageCount': pageCount,
        'lastPage': lastPage,
        'completed': completed,
        'timestamp': timestamp.toIso8601String(),
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        bookId: json['bookId'] as String,
        seriesId: json['seriesId'] as String,
        bookTitle: json['bookTitle'] as String,
        bookNumber: json['bookNumber'] as String,
        pageCount: json['pageCount'] as int,
        lastPage: json['lastPage'] as int,
        completed: json['completed'] as bool,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}
