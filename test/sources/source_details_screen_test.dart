import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:shaddai_reader/app/providers.dart';
import 'package:shaddai_reader/backends/suwayomi/suwayomi_maintenance_client.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';
import 'package:shaddai_reader/core/sources/hidden_sources_store.dart';
import 'package:shaddai_reader/features/suwayomi/source_details_screen.dart';
import 'package:shaddai_reader/features/suwayomi/sources_screen.dart';

class _FakeClient extends SuwayomiMaintenanceClient {
  final changes = <Object>[];
  _FakeClient()
      : super(
          config: const ServerConfig(
            id: 's',
            name: 'Suwayomi',
            type: ServerType.suwayomi,
            baseUrl: 'http://fake',
            username: '',
          ),
        );

  @override
  Future<SourceDetails> sourceDetails(String sourceId) async => SourceDetails(
        id: sourceId,
        name: 'Mangabat',
        lang: 'en',
        iconUrl: null,
        homeUrl: 'https://www.mangabats.com',
        supportsLatest: true,
        rating: ContentRating.mixed,
        pkgName: 'eu.kanade.tachiyomi.extension.en.mangabat',
        versionName: '1.6.24',
        repoName: 'Keiyoushi',
        preferences: const [
          BoolPreference(
            position: 0,
            key: 'pref_merge_images',
            title: 'Merge Split Images',
            summary: null,
            visible: true,
            enabled: true,
            value: false,
          ),
        ],
      );

  /// Set to make the health check throw outright.
  Object? checkThrows;

  @override
  Future<SourceCheck> checkSource(String sourceId) async {
    if (checkThrows != null) throw checkThrows!;
    return const SourceCheck([
      SourceCheckStep(name: 'Catalog', took: Duration(milliseconds: 900)),
      SourceCheckStep(name: 'Chapters', took: Duration(milliseconds: 300)),
      SourceCheckStep(name: 'Pages', took: Duration(milliseconds: 200)),
      SourceCheckStep(name: 'Image', took: Duration(milliseconds: 1200), error: 'HTTP 500'),
    ]);
  }

  @override
  Future<void> setSourcePreference(
      String sourceId, SourcePreference pref, Object value) async {
    changes.add(value);
  }
}

void main() {
  setUp(() async => await setUpTestHive());
  tearDown(() async => await tearDownTestHive());

  Future<_FakeClient> pump(WidgetTester tester, {required bool owner}) async {
    // Tablet width, tall enough that every section is built.
    tester.view.physicalSize = const Size(1101, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = _FakeClient();
    final hidden = HiddenSourcesStore();
    await tester.runAsync(hidden.init);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        suwayomiAdminProvider.overrideWith((ref) async => client),
        hiddenSourcesStoreProvider.overrideWithValue(hidden),
        isOwnerProvider.overrideWith((ref) => owner),
      ],
      child: const MaterialApp(home: SourceDetailsScreen(sourceId: '42')),
    ));
    await tester.pumpAndSettle();
    return client;
  }

  testWidgets('a friend gets Browse, not the health check', (tester) async {
    await pump(tester, owner: false);
    expect(find.text('Browse Mangabat'), findsOneWidget);
    expect(find.text('Check source'), findsNothing);
  });

  testWidgets('a failed check says what it means and what to do',
      (tester) async {
    await pump(tester, owner: true);
    await tester.tap(find.text('Check source'));
    await tester.pumpAndSettle();
    expect(find.text('Failing at image'), findsOneWidget);
    expect(find.textContaining("image server refused the page"), findsOneWidget);
    expect(find.text('1.2s'), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);
  });

  testWidgets('a check that throws never leaves the page on Checking',
      (tester) async {
    final client = await pump(tester, owner: true);
    client.checkThrows = Exception('boom');
    await tester.tap(find.text('Check source'));
    await tester.pumpAndSettle();
    expect(find.text('Checking'), findsNothing);
    expect(find.text('Check again'), findsOneWidget);
  });

  testWidgets('a friend sees source settings but cannot change them',
      (tester) async {
    final client = await pump(tester, owner: false);
    expect(find.text('Mangabat'), findsOneWidget);
    expect(find.text('Merge Split Images'), findsOneWidget);
    expect(find.text('Only the server owner can change these.'), findsOneWidget);

    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(client.changes, isEmpty);
  });

  testWidgets('the owner changes a source setting', (tester) async {
    final client = await pump(tester, owner: true);
    expect(find.text('Only the server owner can change these.'), findsNothing);

    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(client.changes, [true]);
  });

  testWidgets('hiding the source is remembered for this account',
      (tester) async {
    await pump(tester, owner: false);
    await tester.runAsync(() async {
      await tester.tap(find.byType(Switch).first);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(SourceDetailsScreen)));
    expect(container.read(hiddenSourcesStoreProvider).isHidden('42'), isTrue);
  });
}
