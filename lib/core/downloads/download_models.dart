enum DownloadState { queued, running, paused, done, failed }

/// A single book's place in the download queue. One task per book; a
/// "download this series/volume" action just enqueues many of these.
class DownloadTask {
  final String bookId;
  final String seriesId;
  final String seriesTitle;
  final String title;
  final int totalPages;
  final int downloadedPages;
  final DownloadState state;
  final String? error;

  /// Which server the book lives on - the queue can hold books from several,
  /// and a page must be fetched from the one it came from. Null only for
  /// tasks saved before this was recorded.
  final String? serverId;

  /// Position in the queue (lower runs first). Lets the user rearrange it;
  /// Hive itself returns tasks in key order, which means nothing here.
  final int order;

  const DownloadTask({
    required this.bookId,
    required this.seriesId,
    required this.seriesTitle,
    required this.title,
    required this.totalPages,
    this.downloadedPages = 0,
    this.state = DownloadState.queued,
    this.error,
    this.serverId,
    this.order = 0,
  });

  double get progress => totalPages == 0 ? 0 : downloadedPages / totalPages;

  DownloadTask copyWith({
    int? totalPages,
    int? downloadedPages,
    DownloadState? state,
    String? error,
    int? order,
  }) {
    return DownloadTask(
      bookId: bookId,
      seriesId: seriesId,
      seriesTitle: seriesTitle,
      title: title,
      totalPages: totalPages ?? this.totalPages,
      downloadedPages: downloadedPages ?? this.downloadedPages,
      state: state ?? this.state,
      // A retry (any other state) drops the old error; a reorder or progress
      // update of a failed task keeps it.
      error: error ??
          (state == null || state == DownloadState.failed ? this.error : null),
      serverId: serverId,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() => {
        'bookId': bookId,
        'seriesId': seriesId,
        'seriesTitle': seriesTitle,
        'title': title,
        'totalPages': totalPages,
        'downloadedPages': downloadedPages,
        'state': state.name,
        'error': error,
        'serverId': serverId,
        'order': order,
      };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
        bookId: json['bookId'] as String,
        seriesId: json['seriesId'] as String,
        seriesTitle: json['seriesTitle'] as String? ?? '',
        title: json['title'] as String,
        totalPages: json['totalPages'] as int,
        downloadedPages: json['downloadedPages'] as int? ?? 0,
        state: DownloadState.values.byName(json['state'] as String),
        error: json['error'] as String?,
        serverId: json['serverId'] as String?,
        order: json['order'] as int? ?? 0,
      );
}
