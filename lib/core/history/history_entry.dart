/// One reading session recorded locally (6e History). Written when a
/// reader session ends (dispose), upserted per book so reopening the same
/// chapter updates its existing row instead of duplicating it.
class HistoryEntry {
  /// The server this was read on. Null for entries recorded before this
  /// existed, or synced from a device where that server id isn't known.
  final String? serverId;

  /// [ServerConfig.portableKey] of that server, so another device can find
  /// its own id for it.
  final String? serverKey;
  final String bookId;
  final String seriesId;
  final String bookTitle;
  final String bookNumber;
  final int pageCount;
  final int lastPage;
  final bool completed;
  final DateTime timestamp;

  const HistoryEntry({
    this.serverId,
    this.serverKey,
    required this.bookId,
    required this.seriesId,
    required this.bookTitle,
    required this.bookNumber,
    required this.pageCount,
    required this.lastPage,
    required this.completed,
    required this.timestamp,
  });

  HistoryEntry withServerId(String? id) => HistoryEntry(
        serverId: id,
        serverKey: serverKey,
        bookId: bookId,
        seriesId: seriesId,
        bookTitle: bookTitle,
        bookNumber: bookNumber,
        pageCount: pageCount,
        lastPage: lastPage,
        completed: completed,
        timestamp: timestamp,
      );

  Map<String, dynamic> toJson() => {
        'serverId': serverId,
        'serverKey': serverKey,
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
        serverId: json['serverId'] as String?,
        serverKey: json['serverKey'] as String?,
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
