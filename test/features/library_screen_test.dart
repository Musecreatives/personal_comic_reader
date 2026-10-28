import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hive_test/hive_test.dart';
import 'package:shaddai_reader/app/providers.dart';
import 'package:shaddai_reader/core/collections/collections_store.dart';
import 'package:shaddai_reader/core/backend/models.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';
import 'package:shaddai_reader/features/library/library_screen.dart';

class _FakeBackend implements ReaderBackend {
  final List<Series> series;
  final Object? failWith;
  _FakeBackend(this.series, {this.failWith});

  @override
  ServerConfig get config => const ServerConfig(
        id: 'fake',
        name: 'Fake',
        type: ServerType.komga,
        baseUrl: 'http://fake.local',
        username: 'u',
      );

  final List<String> requestedLibraryIds = [];

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
    if (libraryId != null) requestedLibraryIds.add(libraryId);
    if (failWith != null) throw failWith!;
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

  @override
  Future<List<Library>> listLibraries() async => const [
        Library(id: 'lib1', name: 'Lib One'),
        Library(id: 'lib2', name: 'Lib Two'),
      ];

  // Unused by LibraryScreen - not exercised in this test.
  @override
  Future<void> authenticate() => throw UnimplementedError();
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
  late CollectionsStore collections;
  setUp(() async {
    await setUpTestHive();
    collections = CollectionsStore();
    await collections.init();
  });
  tearDown(() async => await tearDownTestHive());

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
          collectionsStoreProvider.overrideWithValue(collections),
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

  testWidgets(
      'on a wide screen, tapping a different library chip reloads series '
      'for that library', (tester) async {
    final fakeBackend = _FakeBackend([
      const Series(
        id: 's1',
        libraryId: 'lib1',
        title: 'Absolute Batman',
        booksCount: 1,
        booksReadCount: 0,
        booksUnreadCount: 1,
      ),
    ]);

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBackendProvider.overrideWith((ref) async => fakeBackend),
          collectionsStoreProvider.overrideWithValue(collections),
        ],
        child: const MaterialApp(
          home: LibraryScreen(libraryId: 'lib1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Libraries are a chip row at every width (no side pane).
    expect(find.text('Lib One'), findsOneWidget);
    expect(find.text('Lib Two'), findsOneWidget);
    expect(fakeBackend.requestedLibraryIds, contains('lib1'));

    await tester.tap(find.text('Lib Two'));
    await tester.pumpAndSettle();

    expect(fakeBackend.requestedLibraryIds.last, 'lib2');
  });

  Future<void> pumpLibrary(WidgetTester tester, _FakeBackend backend) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBackendProvider.overrideWith((ref) async => backend),
          collectionsStoreProvider.overrideWithValue(collections),
        ],
        child: const MaterialApp(home: LibraryScreen(libraryId: 'lib1')),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Phone, tablet landscape, tablet portrait (DESIGN.md: check both).
  for (final size in const [Size(390, 844), Size(1101, 688), Size(688, 1101)]) {
    testWidgets('lays out a full shelf without overflow at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpLibrary(
        tester,
        _FakeBackend([
          for (var i = 0; i < 30; i++)
            Series(
              id: 's$i',
              libraryId: 'lib1',
              title: 'A rather long series title number $i',
              booksCount: 10,
              booksReadCount: i % 11,
              booksUnreadCount: 10 - i % 11,
            ),
        ]),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('A rather long series title number 0'), findsOneWidget);
    });
  }

  testWidgets('an empty library shows the empty state', (tester) async {
    await pumpLibrary(tester, _FakeBackend(const []));
    expect(find.text('This shelf is empty'), findsOneWidget);
  });

  testWidgets('a failed load shows the error with a retry', (tester) async {
    await pumpLibrary(
        tester, _FakeBackend(const [], failWith: Exception('SocketException')));
    expect(find.text("Can't reach the server"), findsWidgets);
    expect(find.text('This shelf is empty'), findsNothing);
  });
}
