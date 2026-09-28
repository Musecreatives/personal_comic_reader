import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';

/// One imported archive/folder - shown as a "series" holding one or more
/// chapters (multiple archives sharing a title group under one record).
class LocalSeriesRecord {
  final String id;
  final String title;
  final DateTime addedAt;

  /// Which media-pool folder "Upload to media pool" targets - 'comic' or
  /// 'manga'. Null until the user is asked (or answers) the first time they
  /// upload this series; there's no reliable way to infer it from the file.
  final String? contentKind;

  const LocalSeriesRecord({
    required this.id,
    required this.title,
    required this.addedAt,
    this.contentKind,
  });

  LocalSeriesRecord copyWith({String? title, String? contentKind}) =>
      LocalSeriesRecord(
        id: id,
        title: title ?? this.title,
        addedAt: addedAt,
        contentKind: contentKind ?? this.contentKind,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'addedAt': addedAt.toIso8601String(),
        if (contentKind != null) 'contentKind': contentKind,
      };

  factory LocalSeriesRecord.fromJson(Map<String, dynamic> json) =>
      LocalSeriesRecord(
        id: json['id'] as String,
        title: json['title'] as String,
        addedAt: DateTime.parse(json['addedAt'] as String),
        contentKind: json['contentKind'] as String?,
      );
}

class LocalBookRecord {
  final String id;
  final String seriesId;
  final String title;
  final String number;
  final int pageCount;
  final int readProgressPage;
  final bool completed;
  final DateTime addedAt;

  const LocalBookRecord({
    required this.id,
    required this.seriesId,
    required this.title,
    required this.number,
    required this.pageCount,
    this.readProgressPage = 0,
    this.completed = false,
    required this.addedAt,
  });

  LocalBookRecord copyWith({
    String? title,
    String? number,
    int? readProgressPage,
    bool? completed,
  }) =>
      LocalBookRecord(
        id: id,
        seriesId: seriesId,
        title: title ?? this.title,
        number: number ?? this.number,
        pageCount: pageCount,
        readProgressPage: readProgressPage ?? this.readProgressPage,
        completed: completed ?? this.completed,
        addedAt: addedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'seriesId': seriesId,
        'title': title,
        'number': number,
        'pageCount': pageCount,
        'readProgressPage': readProgressPage,
        'completed': completed,
        'addedAt': addedAt.toIso8601String(),
      };

  factory LocalBookRecord.fromJson(Map<String, dynamic> json) =>
      LocalBookRecord(
        id: json['id'] as String,
        seriesId: json['seriesId'] as String,
        title: json['title'] as String,
        number: json['number'] as String,
        pageCount: json['pageCount'] as int,
        readProgressPage: json['readProgressPage'] as int? ?? 0,
        completed: json['completed'] as bool? ?? false,
        addedAt: DateTime.parse(json['addedAt'] as String),
      );
}

/// Backing store for manually-imported comics/manga. Every page is unpacked
/// once at import time - there's no remote server to stream pages from, so
/// an imported book is always fully "on device".
///
/// Series and book metadata are JSON strings in two Hive boxes. Page images
/// are plain files under [pagesDir] (`<bookId>/<pageIndex>`) on desktop and
/// mobile: a Hive box is read fully into memory when it opens, and a single
/// omnibus can be gigabytes. Web has no filesystem, so there (and when
/// [pagesDir] is null) pages go in a Hive box keyed `<bookId>|<pageIndex>`.
class LocalLibraryStore {
  static const _seriesBoxName = 'local_library_series';
  static const _booksBoxName = 'local_library_books';
  static const _pagesBoxName = 'local_library_pages';

  final Directory? pagesDir;

  late final Box<String> _seriesBox;
  late final Box<String> _booksBox;
  Box<Uint8List>? _pagesBox;

  LocalLibraryStore({this.pagesDir});

  Future<void> init() async {
    _seriesBox = await Hive.openBox<String>(_seriesBoxName);
    _booksBox = await Hive.openBox<String>(_booksBoxName);
    if (pagesDir == null) {
      _pagesBox = await Hive.openBox<Uint8List>(_pagesBoxName);
    } else {
      await pagesDir!.create(recursive: true);
    }
  }

  File _pagePath(String bookId, int pageIndex) =>
      File('${pagesDir!.path}${Platform.pathSeparator}$bookId'
          '${Platform.pathSeparator}$pageIndex');

  List<LocalSeriesRecord> listSeries() => _seriesBox.values
      .map((raw) =>
          LocalSeriesRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>))
      .toList()
    ..sort((a, b) => b.addedAt.compareTo(a.addedAt));

  LocalSeriesRecord? getSeries(String id) {
    final raw = _seriesBox.get(id);
    if (raw == null) return null;
    return LocalSeriesRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> putSeries(LocalSeriesRecord series) =>
      _seriesBox.put(series.id, jsonEncode(series.toJson()));

  List<LocalBookRecord> listBooksForSeries(String seriesId) => _booksBox.values
      .map((raw) =>
          LocalBookRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>))
      .where((b) => b.seriesId == seriesId)
      .toList()
    ..sort(_byNumber);

  // Numeric where possible, so chapter "10" sorts after "2".
  static int _byNumber(LocalBookRecord a, LocalBookRecord b) {
    final an = double.tryParse(a.number), bn = double.tryParse(b.number);
    if (an != null && bn != null) return an.compareTo(bn);
    return a.number.compareTo(b.number);
  }

  List<LocalBookRecord> listAllBooks() => _booksBox.values
      .map((raw) =>
          LocalBookRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>))
      .toList();

  LocalBookRecord? getBook(String id) {
    final raw = _booksBox.get(id);
    if (raw == null) return null;
    return LocalBookRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> putBook(LocalBookRecord book) =>
      _booksBox.put(book.id, jsonEncode(book.toJson()));

  Future<void> putPage(String bookId, int pageIndex, Uint8List bytes) async {
    if (pagesDir == null) {
      return _pagesBox!.put('$bookId|$pageIndex', bytes);
    }
    final file = _pagePath(bookId, pageIndex);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  /// Stores an image that's already on disk without reading it into memory.
  /// Copies [source] unless [move] is set (for temp files the caller owns),
  /// in which case it's renamed into place - instant on the same drive.
  Future<void> putPageFromFile(
    String bookId,
    int pageIndex,
    File source, {
    bool move = false,
  }) async {
    if (pagesDir == null) {
      return putPage(bookId, pageIndex, await source.readAsBytes());
    }
    final file = _pagePath(bookId, pageIndex);
    await file.parent.create(recursive: true);
    if (move) {
      try {
        await source.rename(file.path);
        return;
      } on FileSystemException {
        // Different drive/volume - fall through to a copy.
      }
    }
    await source.copy(file.path);
  }

  Future<Uint8List?> getPage(String bookId, int pageIndex) async {
    if (pagesDir == null) return _pagesBox!.get('$bookId|$pageIndex');
    final file = _pagePath(bookId, pageIndex);
    return await file.exists() ? file.readAsBytes() : null;
  }

  /// The page's file, for callers that can use it directly (e.g. to decode
  /// a thumbnail without holding the full image). Null on web.
  File? pageFile(String bookId, int pageIndex) {
    if (pagesDir == null) return null;
    final file = _pagePath(bookId, pageIndex);
    return file.existsSync() ? file : null;
  }

  /// Removes every stored page of [bookId] - also used to clean up an
  /// import that failed part-way through.
  Future<void> deletePages(String bookId, int pageCount) async {
    if (pagesDir == null) {
      await _pagesBox!
          .deleteAll([for (var i = 0; i < pageCount; i++) '$bookId|$i']);
      return;
    }
    final dir = Directory('${pagesDir!.path}${Platform.pathSeparator}$bookId');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Removes a book, its pages, and (if it was the series' last book) the
  /// series entry too.
  Future<void> deleteBook(String bookId) async {
    final book = getBook(bookId);
    if (book == null) return;
    await deletePages(bookId, book.pageCount);
    await _booksBox.delete(bookId);
    if (listBooksForSeries(book.seriesId).isEmpty) {
      await _seriesBox.delete(book.seriesId);
    }
  }
}
