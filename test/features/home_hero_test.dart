import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';

import 'package:shaddai_reader/app/platform_style.dart';
import 'package:shaddai_reader/app/providers.dart';
import 'package:shaddai_reader/app/theme.dart';
import 'package:shaddai_reader/core/appearance/appearance_settings.dart';
import 'package:shaddai_reader/core/backend/models.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';
import 'package:shaddai_reader/core/downloads/download_store.dart';
import 'package:shaddai_reader/core/history/history_entry.dart';
import 'package:shaddai_reader/core/history/stopped_series_store.dart';
import 'package:shaddai_reader/features/discovery/discovery_providers.dart';
import 'package:shaddai_reader/features/home/home_feed.dart';
import 'package:shaddai_reader/features/home/home_screen.dart';
import 'package:shaddai_reader/features/shared/series_cover.dart';

/// A backend that can be "down": every call throws, like an unreachable
/// server.
class _Backend implements ReaderBackend {
  @override
  final ServerConfig config;
  final bool down;
  _Backend(this.config, {this.down = false});

  @override
  Future<Series> getSeries(String id) async =>
      down ? throw Exception('no route') : throw UnimplementedError();
  @override
  Future<List<Book>> listBooks(String seriesId) async =>
      down ? throw Exception('no route') : const [];
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
  Future<Uri> pageUri(String bookId, int pageIndex) => throw UnimplementedError();
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

const _komga = ServerConfig(
    id: 'k', name: 'Paulostic', type: ServerType.komga, baseUrl: 'https://k', username: 'u');
const _suwayomi = ServerConfig(
    id: 's', name: 'Paulostic', type: ServerType.suwayomi, baseUrl: 'http://s', username: '');

void main() {
  late DownloadStore downloads;
  late StoppedSeriesStore stopped;

  setUp(() async {
    await setUpTestHive();
    downloads = DownloadStore();
    await downloads.init();
    stopped = StoppedSeriesStore();
    await stopped.init();
  });
  tearDown(() async => await tearDownTestHive());

  test('the outage line says what is down and what still works', () {
    expect(outageMessage(down: ['Suwayomi'], fine: ['Komga']),
        "Suwayomi isn't answering. Komga and your downloads are fine.");
    expect(outageMessage(down: ['Komga', 'Suwayomi'], fine: []),
        "Komga and Suwayomi aren't answering. Your downloads are fine.");
  });

  // Suwayomi is down and the last thing read was on it: Home must still lead
  // with it (offline), not lose it. Checked at the Android tablet's real
  // landscape and portrait sizes and on a phone.
  for (final (name, size, split) in const [
    ('tablet landscape', Size(1101, 688), true),
    ('tablet portrait', Size(688, 1101), false),
    ('phone', Size(390, 844), false),
  ]) {
    testWidgets('$name: last read stays on Home while its server is down',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      PlatformStyle.configure(InterfaceStyle.android);
      addTearDown(() => PlatformStyle.configure(InterfaceStyle.auto));

      final komga = _Backend(_komga);
      final suwayomi = _Backend(_suwayomi, down: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeServerIdProvider.overrideWith((ref) => 'k'),
            activeBackendProvider.overrideWith((ref) async => komga),
            serverListProvider.overrideWithValue(const [_komga, _suwayomi]),
            homeFeedProvider.overrideWith((ref) async => const HomeFeed(
                  inProgress: [],
                  recent: [],
                  unreachable: [_suwayomi],
                )),
            recentReadingProvider.overrideWithValue([
              HistoryEntry(
                serverId: 's',
                bookId: 'c181',
                seriesId: 'solo',
                bookTitle: 'Chapter 181',
                bookNumber: '181',
                pageCount: 22,
                lastPage: 13,
                completed: false,
                timestamp: DateTime.now(),
              ),
            ]),
            backendForServerProvider
                .overrideWith((ref, id) async => id == 's' ? suwayomi : komga),
            downloadStoreProvider.overrideWithValue(downloads),
            stoppedSeriesStoreProvider.overrideWithValue(stopped),
            cachedRecommendationsProvider.overrideWith((ref) async => const []),
          ],
          child: MaterialApp(
            theme: buildAppTheme(const AppearanceSettings()),
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('SUWAYOMI · OFFLINE'), findsOneWidget);
      expect(find.text('Chapter 181'), findsOneWidget);
      expect(find.textContaining('page 14 of 22'), findsOneWidget);
      expect(find.text("Suwayomi isn't answering. Komga and your downloads are fine."),
          findsOneWidget);
      final cover = tester.getSize(find.byType(SeriesCover).first);
      // Landscape tablet: the board's split, a 230x330 cover (its 2px ink
      // edge drawn over it) beside the text. Otherwise the cover fills the
      // hero's width.
      expect(cover, split ? const Size(230, 330) : Size(size.width, cover.height));
    });
  }
}
