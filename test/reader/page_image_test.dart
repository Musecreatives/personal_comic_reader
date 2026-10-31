import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';
import 'package:shaddai_reader/core/reader/page_cache.dart';
import 'package:shaddai_reader/features/reader/widgets/page_image.dart';

class _FixedCache extends PageCache {
  final Uint8List bytes;
  _FixedCache(this.bytes);

  @override
  Future<Uint8List> getPage(ReaderBackend backend, String bookId, int pageIndex) async => bytes;
}

class _NoBackend implements ReaderBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.white,
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  Future<double?> pump(WidgetTester tester, Uint8List bytes) async {
    double? ratio;
    await tester.pumpWidget(MaterialApp(
      home: PageImage(
        backend: _NoBackend(),
        pageCache: _FixedCache(bytes),
        bookId: 'b',
        pageIndex: 0,
        fit: BoxFit.contain,
        scrollTall: true,
        onAspectRatio: (r) => ratio = r,
      ),
    ));
    // Header read and image decode happen off the fake clock.
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    return ratio;
  }

  testWidgets('a long strip page fills the width and scrolls', (tester) async {
    final bytes = (await tester.runAsync(() => _png(40, 800)))!;
    final ratio = await pump(tester, bytes);
    expect(ratio, closeTo(0.05, 0.001));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.fitWidth);
  });

  testWidgets('a normal page keeps the chosen fit', (tester) async {
    final bytes = (await tester.runAsync(() => _png(70, 100)))!;
    await pump(tester, bytes);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
  });
}
