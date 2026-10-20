import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shaddai_reader/app/providers.dart';
import 'package:shaddai_reader/core/backend/models.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';
import 'package:shaddai_reader/features/series/series_screen.dart';

class _FakeBackend implements ReaderBackend {
  final Series series;
  final List<Book> books;
  _FakeBackend(this.series, this.books);

  @override
  ServerConfig get config => const ServerConfig(
        id: 'fake',
        name: 'Fake',
        type: ServerType.komga,
        baseUrl: 'http://fake.local',
        username: 'u',
      );

  @override
  Future<Series> getSeries(String id) async => series;
  @override
  Future<List<Book>> listBooks(String seriesId) async => books;
  @override
  Map<String, String> get imageHeaders => const {};

  @override
  Future<void> authenticate() => throw UnimplementedError();
  @override
  Future<PagedResult<Series>> listSeries({
    String? libraryId,
    int page = 0,
    int size = 20,
    SeriesSort sort = SeriesSort.title,
    SortDirection direction = SortDirection.asc,
    bool unreadOnly = false,
    String? search,
  }) =>
      throw UnimplementedError();
  @override
  Future<List<Library>> listLibraries() => throw UnimplementedError();
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
  testWidgets(
      'on a wide (desktop) screen, the chapter list actually renders rows',
      (tester) async {
    final series = const Series(
      id: 's1',
      libraryId: 'lib1',
      title: 'Test Series',
      booksCount: 5,
      booksReadCount: 0,
      booksUnreadCount: 5,
    );
    final books = List.generate(
      5,
      (i) => Book(
        id: 'b$i',
        seriesId: 's1',
        title: 'Chapter $i',
        number: '$i',
        pageCount: 10,
        completed: false,
      ),
    );
    final fakeBackend = _FakeBackend(series, books);

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBackendProvider.overrideWith((ref) async => fakeBackend),
        ],
        child: const MaterialApp(
          home: SeriesScreen(seriesId: 's1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Chapter 0'), findsOneWidget);
    expect(find.text('Chapter 4'), findsOneWidget);
  });
}
