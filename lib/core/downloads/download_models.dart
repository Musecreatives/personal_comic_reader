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

  const DownloadTask({
    required this.bookId,
    required this.seriesId,
    required this.seriesTitle,
    required this.title,
    required this.totalPages,
    this.downloadedPages = 0,
    this.state = DownloadState.queued,
    this.error,
  });

  double get progress => totalPages == 0 ? 0 : downloadedPages / totalPages;

  DownloadTask copyWith({
    int? downloadedPages,
    DownloadState? state,
    String? error,
  }) {
    return DownloadTask(
      bookId: bookId,
      seriesId: seriesId,
      seriesTitle: seriesTitle,
      title: title,
      totalPages: totalPages,
      downloadedPages: downloadedPages ?? this.downloadedPages,
      state: state ?? this.state,
      error: error,
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
      );
}
