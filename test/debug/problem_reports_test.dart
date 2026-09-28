import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/core/debug/debug_log.dart';
import 'package:shaddai_reader/core/debug/problem_reports.dart';

void main() {
  test('network calls are recorded without sign-in bodies, and reports carry them',
      () async {
    final log = DebugLog.instance..clear();
    final dio = trackedDio(BaseOptions(baseUrl: 'http://127.0.0.1:9'));
    final bodies = {
      '/auth/login': {'username': 'u', 'password': 'secret'},
      '/api/graphql': {'query': '{ x }'},
    };
    for (final MapEntry(key: path, value: body) in bodies.entries) {
      try {
        await dio.post(path, data: body);
      } catch (_) {} // nothing listens on port 9
    }
    log.log('opened series');

    expect(log.network, hasLength(2));
    expect(log.network.first.requestBody, isNull);
    expect(log.network.last.requestBody, contains('query'));
    expect(log.network.every((e) => e.failed), isTrue);

    final report = buildReport(
        kind: ReportKind.crash, title: 't', details: '', error: 'FormatException');
    expect(report['status'], 'open');
    expect(report['network'], hasLength(2));
    expect((report['logs'] as List).last['message'], 'opened series');
    expect('$report', isNot(contains('secret')));
  });
}
