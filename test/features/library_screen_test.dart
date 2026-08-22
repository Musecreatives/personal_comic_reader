import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shaddai_reader/app/providers.dart';
import 'package:shaddai_reader/core/backend/models.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';
import 'package:shaddai_reader/features/library/library_screen.dart';

class _FakeBackend implements ReaderBackend {
  final List<Series> series;
  _FakeBackend(this.series);

  @override
  ServerConfig get config => const ServerConfig(
        id: 'fake',
        name: 'Fake',
        type: ServerType.komga,
        baseUrl: 'http://fake.local',
        username: 'u',
      );

  @override
  Future<PagedResult<Series>> listSeries({
    String? libraryId,
    int page = 0,
    int size = 20,
    SeriesSort sort = SeriesSort.title,
    SortDirection direction = SortDirection.asc,
    bool unreadOnly = false,
    String? search,
  }) async {
    return PagedResult(
      items: series,
      page: 0,
      size: series.length,
      totalPages: 1,
      totalElements: series.length,
    );
  }

  @override
  Map<String, String> get imageHeaders => const {};

  // Unused by LibraryScreen - not exercised in this test.
  @override
  Future<void> authenticate() => throw UnimplementedError();
  @override
  Future<List<Library>> listLibraries() => throw UnimplementedError();
  @override
  Future<Series> getSeries(String id) => throw UnimplementedError();
  @override
  Future<List<Book>> listBooks(String seriesId) => throw UnimplementedError();
  @override
  Future<Book> getBook(String id) => throw UnimplementedError();
  @override
  Future<Uri> pageUri(String bookId, int pageIndex) =>
      throw UnimplementedError();
  @override
  Future<Uint8List> fetchPage(String bookId, int pageIndex) =>
      throw UnimplementedError();
  @override
  Future<void> updateProgress(String bookId,
          {required int page, bool completed = false}) =>
      throw UnimplementedError();
  @override
  Future<List<Series>> continueReading() => throw UnimplementedError();
  @override
  Future<List<Book>> recentlyAdded() => throw UnimplementedError();
  @override
  Future<List<Collection>> listCollections() => throw UnimplementedError();
  @override
  Future<List<ReadList>> listReadLists() => throw UnimplementedError();
  @override
  String thumbnailUrlForSeries(String seriesId) => '';
  @override
  String thumbnailUrlForBook(String bookId) => '';
}

void main() {
  testWidgets('LibraryScreen renders a grid tile per series', (tester) async {
    final fakeBackend = _FakeBackend([
      const Series(
        id: 's1',
        libraryId: 'lib1',
        title: 'Absolute Batman',
        booksCount: 5,
        booksReadCount: 2,
        booksUnreadCount: 3,
      ),
      const Series(
        id: 's2',
        libraryId: 'lib1',
        title: 'One Piece',
        booksCount: 100,
        booksReadCount: 100,
        booksUnreadCount: 0,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBackendProvider.overrideWith((ref) async => fakeBackend),
        ],
        child: const MaterialApp(
          home: LibraryScreen(libraryId: 'lib1'),
        ),
      ),
    );

    // Let the FutureProvider and the initial listSeries() call settle.
    await tester.pumpAndSettle();

    expect(find.text('Absolute Batman'), findsOneWidget);
    expect(find.text('One Piece'), findsOneWidget);
    // Unread badge only on the series with unread books.
    expect(find.text('3'), findsOneWidget);
  });
}
