import 'dart:typed_data';
import 'dart:ui' as ui;

/// A detected panel's bounds, normalized to 0..1 of the page image.
class PanelRect {
  final double left;
  final double top;
  final double width;
  final double height;

  const PanelRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  static const wholePage = PanelRect(left: 0, top: 0, width: 1, height: 1);
}

/// Experimental, deliberately simple panel detection: finds gutters (rows/
/// columns that are almost entirely near-white or near-black) to split a
/// page into a grid of panels, ordered top-to-bottom then left-to-right
/// (or right-to-left for [rtl]). This is a heuristic over comics that use
/// a regular grid with visible gutters - it will get non-grid layouts,
/// bleeds, and borderless panels wrong. Kept intentionally rough per the
/// smart-panel-view feature's own scope.
Future<List<PanelRect>> detectPanels(
  Uint8List pageBytes, {
  bool rtl = false,
  int targetWidth = 400,
}) async {
  final codec =
      await ui.instantiateImageCodec(pageBytes, targetWidth: targetWidth);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final width = image.width;
  final height = image.height;
  image.dispose();

  if (byteData == null) return const [PanelRect.wholePage];
  return panelsFromRgba(byteData.buffer.asUint8List(), width, height, rtl: rtl);
}

/// The pure geometry half of [detectPanels], split out so it's testable
/// without decoding a real image - feed it a synthetic RGBA buffer.
List<PanelRect> panelsFromRgba(
  Uint8List rgba,
  int width,
  int height, {
  bool rtl = false,
  double varianceThreshold = 15,
}) {
  if (width <= 0 || height <= 0) return const [PanelRect.wholePage];

  double luminanceAt(int x, int y) {
    final i = (y * width + x) * 4;
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    return 0.299 * r + 0.587 * g + 0.114 * b;
  }

  // A gutter is a row/column that's a single roughly-flat color - the page
  // background (usually white, but this doesn't assume that) rather than
  // varied panel artwork. Whether that flat color happens to be white,
  // black, or gray doesn't matter; only that it barely varies.
  bool isGutterRow(int y) {
    double? min, max;
    for (var x = 0; x < width; x += 2) {
      final luma = luminanceAt(x, y);
      min = min == null ? luma : (luma < min ? luma : min);
      max = max == null ? luma : (luma > max ? luma : max);
    }
    return min == null || (max! - min) < varianceThreshold;
  }

  bool isGutterCol(int x, int yStart, int yEnd) {
    double? min, max;
    for (var y = yStart; y < yEnd; y += 2) {
      final luma = luminanceAt(x, y);
      min = min == null ? luma : (luma < min ? luma : min);
      max = max == null ? luma : (luma > max ? luma : max);
    }
    return min == null || (max! - min) < varianceThreshold;
  }

  final rowBands = <(int, int)>[];
  int? bandStart;
  for (var y = 0; y < height; y++) {
    final gutter = isGutterRow(y);
    if (!gutter && bandStart == null) bandStart = y;
    if (gutter && bandStart != null) {
      rowBands.add((bandStart, y));
      bandStart = null;
    }
  }
  if (bandStart != null) rowBands.add((bandStart, height));
  if (rowBands.isEmpty) return const [PanelRect.wholePage];

  final panels = <PanelRect>[];
  for (final (yStart, yEnd) in rowBands) {
    var colBands = <(int, int)>[];
    int? colStart;
    for (var x = 0; x < width; x++) {
      final gutter = isGutterCol(x, yStart, yEnd);
      if (!gutter && colStart == null) colStart = x;
      if (gutter && colStart != null) {
        colBands.add((colStart, x));
        colStart = null;
      }
    }
    if (colStart != null) colBands.add((colStart, width));
    if (colBands.isEmpty) colBands = [(0, width)];
    if (rtl) colBands = colBands.reversed.toList();

    for (final (xStart, xEnd) in colBands) {
      panels.add(PanelRect(
        left: xStart / width,
        top: yStart / height,
        width: (xEnd - xStart) / width,
        height: (yEnd - yStart) / height,
      ));
    }
  }
  return panels;
}
