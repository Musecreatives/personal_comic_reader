import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';

/// One imported archive/folder - shown as a "series" holding one or more
/// chapters (multiple archives sharing a title group under one record).
class LocalSeriesRecord {
  final String id;
  final String title;
  final DateTime addedAt;

  const LocalSeriesRecord({
    required this.id,
    required this.title,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'addedAt': addedAt.toIso8601String(),
      };

  factory LocalSeriesRecord.fromJson(Map<String, dynamic> json) =>
      LocalSeriesRecord(
        id: json['id'] as String,
        title: json['title'] as String,
        addedAt: DateTime.parse(json['addedAt'] as String),
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

/// Backing store for manually-imported comics/manga (CBZ/ZIP archives, or a
/// folder of loose image files). Every page is decoded once at import time
/// and its bytes kept in Hive - there's no remote server to stream pages
/// from, so an imported book is always fully "on device".
///
/// Three boxes: series metadata, book metadata (both JSON strings), and page
/// bytes keyed `<bookId>|<pageIndex>`.
class LocalLibraryStore {
  static const _seriesBoxName = 'local_library_series';
  static const _booksBoxName = 'local_library_books';
  static const _pagesBoxName = 'local_library_pages';

  late final Box<String> _seriesBox;
  late final Box<String> _booksBox;
  late final Box<Uint8List> _pagesBox;

  Future<void> init() async {
    _seriesBox = await Hive.openBox<String>(_seriesBoxName);
    _booksBox = await Hive.openBox<String>(_booksBoxName);
    _pagesBox = await Hive.openBox<Uint8List>(_pagesBoxName);
  }

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
    ..sort((a, b) => a.number.compareTo(b.number));

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

  Future<void> putPage(String bookId, int pageIndex, Uint8List bytes) =>
      _pagesBox.put('$bookId|$pageIndex', bytes);

  Uint8List? getPage(String bookId, int pageIndex) =>
      _pagesBox.get('$bookId|$pageIndex');

  /// Removes a book, its pages, and (if it was the series' last book) the
  /// series entry too.
  Future<void> deleteBook(String bookId) async {
    final book = getBook(bookId);
    if (book == null) return;
    for (var i = 0; i < book.pageCount; i++) {
      await _pagesBox.delete('$bookId|$i');
    }
    await _booksBox.delete(bookId);
    if (listBooksForSeries(book.seriesId).isEmpty) {
      await _seriesBox.delete(book.seriesId);
    }
  }
}
