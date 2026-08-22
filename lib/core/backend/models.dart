/// Plain data models shared by every [ReaderBackend] implementation.
///
/// These are intentionally server-agnostic: each backend adapter is
/// responsible for mapping its own wire format onto these types.
library;

class PagedResult<T> {
  final List<T> items;
  final int page;
  final int size;
  final int totalPages;
  final int totalElements;

  const PagedResult({
    required this.items,
    required this.page,
    required this.size,
    required this.totalPages,
    required this.totalElements,
  });

  bool get hasNext => page + 1 < totalPages;
}

class Library {
  final String id;
  final String name;

  const Library({required this.id, required this.name});
}

class Series {
  final String id;
  final String libraryId;
  final String title;
  final String? summary;
  final int booksCount;
  final int booksReadCount;
  final int booksUnreadCount;
  final String? thumbnailUrl;

  const Series({
    required this.id,
    required this.libraryId,
    required this.title,
    this.summary,
    required this.booksCount,
    required this.booksReadCount,
    required this.booksUnreadCount,
    this.thumbnailUrl,
  });

  bool get isFullyRead => booksCount > 0 && booksUnreadCount == 0;
}

class Book {
  final String id;
  final String seriesId;
  final String title;
  final String number;
  final int pageCount;
  final int? readProgressPage;
  final bool completed;
  final String? thumbnailUrl;

  const Book({
    required this.id,
    required this.seriesId,
    required this.title,
    required this.number,
    required this.pageCount,
    this.readProgressPage,
    required this.completed,
    this.thumbnailUrl,
  });

  double get progressRatio =>
      pageCount == 0 ? 0 : (readProgressPage ?? 0) / pageCount;
}

class Collection {
  final String id;
  final String name;
  final int seriesCount;

  const Collection({
    required this.id,
    required this.name,
    required this.seriesCount,
  });
}

class ReadList {
  final String id;
  final String name;
  final int bookCount;

  const ReadList({
    required this.id,
    required this.name,
    required this.bookCount,
  });
}

enum SeriesSort { title, dateAdded, dateUpdated, releaseDate }

enum SortDirection { asc, desc }
