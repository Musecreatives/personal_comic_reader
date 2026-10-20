import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/backends/suwayomi/suwayomi_backend.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';
import 'package:shaddai_reader/features/search/source_showcase.dart';

class _FakeSuwayomi extends SuwayomiBackend {
  final calls = <String>[];

  _FakeSuwayomi()
      : super(
          config: const ServerConfig(
            id: 's',
            name: 'Suwayomi',
            type: ServerType.suwayomi,
            baseUrl: 'http://fake',
            username: '',
          ),
          password: '',
        );

  @override
  Future<({List<({int id, String title, String thumbnailUrl})> mangas, bool hasNext})>
      browseSource(String sourceId,
          {String query = '', int page = 1, bool latest = false}) async {
    calls.add('$sourceId|${latest ? 'latest' : 'popular'}|$page');
    final label = latest ? 'Latest' : 'Popular';
    return (
      mangas: [
        for (var i = 1; i <= 3; i++)
          (id: i, title: '$label $sourceId $i', thumbnailUrl: ''),
      ],
      hasNext: false,
    );
  }
}

void main() {
  testWidgets('each source shelf shows its popular titles, Latest switches',
      (tester) async {
    final backend = _FakeSuwayomi();
    final cache = SourceListingCache(backend);
    SourceManga? opened;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SourceShelves(
          sources: const [(id: 'a', name: 'Asura Scans', lang: 'en')],
          cache: cache,
          onOpen: (_, m) => opened = m,
          onSeeAll: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Asura Scans'), findsOneWidget);
    expect(find.text('Popular a 1'), findsOneWidget);

    await tester.tap(find.text('LATEST'));
    await tester.pumpAndSettle();
    expect(find.text('Latest a 1'), findsOneWidget);

    // Back to Popular comes from the cache, not a second fetch.
    await tester.tap(find.text('POPULAR'));
    await tester.pumpAndSettle();
    expect(backend.calls, ['a|popular|1', 'a|latest|1']);

    await tester.tap(find.text('Popular a 2'));
    expect(opened?.id, 2);
  });
}
