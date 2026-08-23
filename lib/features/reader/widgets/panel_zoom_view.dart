import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/panels/panel_detector.dart';

/// Experimental smart-panel-view overlay: renders one page, animating
/// between [panels] as the user taps through them. Isolated from the
/// normal pager widgets entirely - it just draws the same page image
/// pre-cropped/zoomed to each panel in turn, using the same BoxFit.contain
/// placement math for both the crop rectangle and the actual paint so the
/// two agree pixel-for-pixel.
class PanelZoomView extends StatefulWidget {
  final Uint8List imageBytes;
  final List<PanelRect> panels;
  final VoidCallback onExhausted;
  final VoidCallback onExit;

  const PanelZoomView({
    super.key,
    required this.imageBytes,
    required this.panels,
    required this.onExhausted,
    required this.onExit,
  });

  @override
  State<PanelZoomView> createState() => _PanelZoomViewState();
}

class _PanelZoomViewState extends State<PanelZoomView> {
  ui.Image? _decoded;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _decoded = frame.image);
  }

  @override
  void dispose() {
    _decoded?.dispose();
    super.dispose();
  }

  void _next() {
    if (_index >= widget.panels.length - 1) {
      widget.onExhausted();
    } else {
      setState(() => _index++);
    }
  }

  void _previous() {
    if (_index > 0) setState(() => _index--);
  }

  @override
  Widget build(BuildContext context) {
    final image = _decoded;
    if (image == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final width = context.size?.width ?? 0;
        if (details.localPosition.dx < width / 3) {
          _previous();
        } else {
          _next();
        }
      },
      onLongPress: widget.onExit,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final viewport = constraints.biggest;
                final rect = widget.panels[_index];
                return TweenAnimationBuilder<Matrix4>(
                  tween: Matrix4Tween(
                    end: _matrixFor(rect, image, viewport),
                  ),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  builder: (context, matrix, child) => ClipRect(
                    child: Transform(
                      transform: matrix,
                      child: child,
                    ),
                  ),
                  child: SizedBox.fromSize(
                    size: viewport,
                    child: CustomPaint(painter: _PagePainter(image)),
                  ),
                );
              },
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Text(
                '${_index + 1} / ${widget.panels.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Matrix4 _matrixFor(PanelRect rect, ui.Image image, Size viewport) {
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, imageSize, viewport);
    final displaySize = fitted.destination;
    final offsetX = (viewport.width - displaySize.width) / 2;
    final offsetY = (viewport.height - displaySize.height) / 2;

    final panelLeft = offsetX + rect.left * displaySize.width;
    final panelTop = offsetY + rect.top * displaySize.height;
    final panelWidth = (rect.width * displaySize.width).clamp(1, viewport.width);
    final panelHeight =
        (rect.height * displaySize.height).clamp(1, viewport.height);

    final zoomScale = [
      viewport.width / panelWidth,
      viewport.height / panelHeight,
    ].reduce((a, b) => a < b ? a : b);

    final panelCenterX = panelLeft + panelWidth / 2;
    final panelCenterY = panelTop + panelHeight / 2;

    return Matrix4.identity()
      ..translateByDouble(viewport.width / 2, viewport.height / 2, 0, 1)
      ..scaleByDouble(zoomScale, zoomScale, zoomScale, 1)
      ..translateByDouble(-panelCenterX, -panelCenterY, 0, 1);
  }
}

class _PagePainter extends CustomPainter {
  final ui.Image image;
  const _PagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, imageSize, size);
    final destRect =
        Alignment.center.inscribe(fitted.destination, Offset.zero & size);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, imageSize.width, imageSize.height),
      destRect,
      Paint(),
    );
  }

  @override
  bool shouldRepaint(covariant _PagePainter oldDelegate) =>
      oldDelegate.image != image;
}
