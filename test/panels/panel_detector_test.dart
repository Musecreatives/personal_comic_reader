import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/core/panels/panel_detector.dart';

/// Builds a synthetic white-background RGBA buffer with a checkerboard
/// pattern painted at each of [rects] (in pixel coordinates: left, top,
/// right, bottom - exclusive), simulating panels with actual artwork
/// variation separated by flat white gutters. A *solid*-color rectangle
/// would be indistinguishable from a gutter to a variance-based detector
/// (it has zero internal variance too) - real panel art always has some
/// texture, which the checkerboard stands in for.
Uint8List _buildImage(
  int width,
  int height,
  List<(int, int, int, int)> rects,
) {
  final buffer = Uint8List(width * height * 4);
  for (var i = 0; i < buffer.length; i += 4) {
    buffer[i] = 255;
    buffer[i + 1] = 255;
    buffer[i + 2] = 255;
    buffer[i + 3] = 255;
  }
  for (final (left, top, right, bottom) in rects) {
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final i = (y * width + x) * 4;
        // Period-8 blocks, not period-2 alternation: the detector samples
        // every other pixel, and a period-2 checkerboard aliases to a flat
        // color under that stride (every sample lands on the same phase).
        final dark = ((x ~/ 4) + (y ~/ 4)) % 2 == 0;
        final value = dark ? 0 : 255;
        buffer[i] = value;
        buffer[i + 1] = value;
        buffer[i + 2] = value;
        buffer[i + 3] = 255;
      }
    }
  }
  return buffer;
}

void main() {
  group('panelsFromRgba', () {
    test('a single full-bleed panel with no gutters yields one whole-page '
        'panel', () {
      const w = 40, h = 40;
      final image = _buildImage(w, h, [(0, 0, w, h)]);

      final panels = panelsFromRgba(image, w, h);

      expect(panels, hasLength(1));
      expect(panels.single.width, 1);
      expect(panels.single.height, 1);
    });

    test('a 2x2 grid separated by white gutters yields 4 panels in reading '
        'order, top row first then left-to-right within each row', () {
      const w = 40, h = 40;
      // Panels at (0-16, 0-16), (20-36, 0-16), (0-16, 20-36), (20-36, 20-36):
      // rows 16-20 and cols 16-20 stay white as gutters.
      final image = _buildImage(w, h, [
        (0, 0, 16, 16),
        (20, 0, 36, 16),
        (0, 20, 16, 36),
        (20, 20, 36, 36),
      ]);

      final panels = panelsFromRgba(image, w, h);

      expect(panels, hasLength(4));
      // Top row (top ~0) comes before bottom row (top ~0.5).
      expect(panels[0].top, lessThan(panels[2].top));
      expect(panels[1].top, lessThan(panels[3].top));
      // Within the top row, left panel comes before right panel (LTR).
      expect(panels[0].left, lessThan(panels[1].left));
      expect(panels[2].left, lessThan(panels[3].left));
    });

    test('rtl reverses left-to-right order within each row', () {
      const w = 40, h = 40;
      final image = _buildImage(w, h, [
        (0, 0, 16, 36),
        (20, 0, 36, 36),
      ]);

      final panels = panelsFromRgba(image, w, h, rtl: true);

      expect(panels, hasLength(2));
      // rtl: the physically-right panel should be read first.
      expect(panels[0].left, greaterThan(panels[1].left));
    });

    test('a zero-sized image degrades to a single whole-page panel', () {
      final panels = panelsFromRgba(Uint8List(0), 0, 0);

      expect(panels, [PanelRect.wholePage]);
    });
  });
}
