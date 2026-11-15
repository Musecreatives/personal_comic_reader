import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shaddai_reader/app/providers.dart';
import 'package:shaddai_reader/core/sync/sync_client.dart';
import 'package:shaddai_reader/features/settings/server_admin_screen.dart';

SyncClient _client() {
  final dio = Dio(BaseOptions(baseUrl: 'https://sync.test'));
  final adapter = DioAdapter(dio: dio);
  dio.httpClientAdapter = adapter;
  final now = DateTime.now().millisecondsSinceEpoch / 1000;
  adapter.onGet('/admin/stats', (s) => s.reply(200, {
        'people': [
          {'id': 1, 'username': 'paul', 'role': 'owner', 'last_seen': now, 'manga_library': 0, 'history': 812},
          {'id': 2, 'username': 'ada', 'role': 'member', 'last_seen': now - 7200, 'manga_library': 295, 'history': 4},
        ],
        'active_7d': 2,
        'requests_waiting': 1,
        'invites_open': 0,
        'source_health': {'ok': 1, 'blocked': 1},
        'alternates': {'total': 549, 'waiting': 120, 'linked': 400, 'errors': 0, 'alternates': 1100},
      }));
  adapter.onGet('/admin/source-health', (s) => s.reply(200, {
        'sources': [
          {'source_id': '1', 'name': 'Asura Scans (EN)', 'status': 'blocked', 'latency': 15.9,
            'checked_at': now - 3600, 'error': 'Exception while fetching data (/fetchChapters) : HTTP error 403\neu...'},
          {'source_id': '2', 'name': 'MangaGeko (EN)', 'status': 'ok', 'latency': 6.9, 'checked_at': now - 3600, 'error': null},
        ],
        'order': ['2', '1'],
      }));
  return SyncClient(baseUrl: 'https://sync.test', dio: dio);
}

void main() {
  for (final size in const [Size(390, 844), Size(1101, 688), Size(688, 1101)]) {
    testWidgets('server overview at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [syncClientProvider.overrideWithValue(_client())],
        child: const MaterialApp(home: ServerAdminScreen()),
      ));
      // The mocked requests finish on the real clock, not the test's.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.text('Sources working'), findsOneWidget);
      // Health is told in words, not only colour.
      expect(find.textContaining('Blocked · 15.9 s'), findsOneWidget);
      expect(find.textContaining('HTTP error 403'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('PEOPLE'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('295 manga'), findsOneWidget);
    });
  }

  test('agoText', () {
    final now = DateTime(2026, 11, 14, 12);
    double at(Duration d) => now.subtract(d).millisecondsSinceEpoch / 1000;
    expect(agoText(null), 'never');
    expect(agoText(at(const Duration(seconds: 30)), now: now), 'just now');
    expect(agoText(at(const Duration(hours: 3)), now: now), '3 h ago');
    expect(agoText(at(const Duration(days: 5)), now: now), '5 d ago');
  });
}
