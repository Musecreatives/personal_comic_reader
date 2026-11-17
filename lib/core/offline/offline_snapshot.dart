import 'dart:async';
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../backend/models.dart';
import '../backend/reader_backend.dart';

/// The last good copy of a series and its chapter list, so a title with
/// downloaded chapters still opens (and its chapters still read) with no
/// connection. Pages themselves live in DownloadStore; this is only the
/// metadata the series screen and reader ask the server for first.
class OfflineSnapshot {
  static const _boxName = 'offline_snapshot';

  /// How long to wait on the server when a saved copy is ready to show
  /// instead. Without a copy the backend's own timeouts apply.
  final Duration fallbackAfter;

  /// Whether the device has no network at all (set by ConnectivityBanner).
  /// Then the saved copy is used straight away instead of waiting for
  /// requests to time out.
  bool offline = false;

  /// Null until [init]: then every call goes straight to the server.
  Box<String>? _box;

  OfflineSnapshot({this.fallbackAfter = const Duration(seconds: 8)});

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  String _key(ReaderBackend b, String kind, String id) =>
      '${b.config.id}|$kind|$id';

  Future<Series> getSeries(ReaderBackend b, String id) => _fetch(
    _key(b, 'series', id),
    () => b.getSeries(id),
    (s) => seriesToJson(s),
    (j) => seriesFromJson(j as Map<String, dynamic>),
  );

  Future<List<Book>> listBooks(ReaderBackend b, String seriesId) async {
    final books = await _fetch(
      _key(b, 'books', seriesId),
      () => b.listBooks(seriesId),
      (list) => [for (final x in list) bookToJson(x)],
      (j) => [
        for (final x in j as List) bookFromJson(x as Map<String, dynamic>),
      ],
    );
    // Each chapter on its own too, so the reader can open one by id.
    unawaited(
      _box?.putAll({
        for (final x in books) _key(b, 'book', x.id): jsonEncode(bookToJson(x)),
      }),
    );
    return books;
  }

  Future<Book> getBook(ReaderBackend b, String id) => _fetch(
    _key(b, 'book', id),
    () => b.getBook(id),
    (x) => bookToJson(x),
    (j) => bookFromJson(j as Map<String, dynamic>),
  );

  Future<T> _fetch<T>(
    String key,
    Future<T> Function() load,
    Object? Function(T) encode,
    T Function(Object?) decode,
  ) async {
    final box = _box;
    if (box == null) return load();
    final raw = box.get(key);
    final saved = raw == null ? null : decode(jsonDecode(raw));
    if (saved != null && offline) return saved;
    try {
      var request = load();
      if (saved != null) request = request.timeout(fallbackAfter);
      final fresh = await request;
      await box.put(key, jsonEncode(encode(fresh)));
      return fresh;
    } catch (_) {
      if (saved != null) return saved;
      rethrow;
    }
  }
}

Map<String, dynamic> seriesToJson(Series s) => {
  'id': s.id,
  'libraryId': s.libraryId,
  'title': s.title,
  'summary': s.summary,
  'booksCount': s.booksCount,
  'booksReadCount': s.booksReadCount,
  'booksUnreadCount': s.booksUnreadCount,
  'thumbnailUrl': s.thumbnailUrl,
  'sourceName': s.sourceName,
  'bannerUrl': s.bannerUrl,
  'credits': s.credits,
  'tags': s.tags,
  'status': s.status?.name,
};

Series seriesFromJson(Map<String, dynamic> j) => Series(
  id: j['id'] as String,
  libraryId: j['libraryId'] as String,
  title: j['title'] as String,
  summary: j['summary'] as String?,
  booksCount: j['booksCount'] as int,
  booksReadCount: j['booksReadCount'] as int,
  booksUnreadCount: j['booksUnreadCount'] as int,
  thumbnailUrl: j['thumbnailUrl'] as String?,
  sourceName: j['sourceName'] as String?,
  bannerUrl: j['bannerUrl'] as String?,
  credits: j['credits'] as String?,
  tags: [for (final t in j['tags'] as List? ?? const []) t as String],
  status: SeriesStatus.values.asNameMap()[j['status']],
);

Map<String, dynamic> bookToJson(Book b) => {
  'id': b.id,
  'seriesId': b.seriesId,
  'title': b.title,
  'number': b.number,
  'pageCount': b.pageCount,
  'readProgressPage': b.readProgressPage,
  'completed': b.completed,
  'thumbnailUrl': b.thumbnailUrl,
  'addedAt': b.addedAt?.toIso8601String(),
};

Book bookFromJson(Map<String, dynamic> j) => Book(
  id: j['id'] as String,
  seriesId: j['seriesId'] as String,
  title: j['title'] as String,
  number: j['number'] as String,
  pageCount: j['pageCount'] as int,
  readProgressPage: j['readProgressPage'] as int?,
  completed: j['completed'] as bool,
  thumbnailUrl: j['thumbnailUrl'] as String?,
  addedAt: DateTime.tryParse(j['addedAt'] as String? ?? ''),
);
