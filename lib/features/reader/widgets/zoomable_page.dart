import 'package:flutter/material.dart';

/// Wraps [child] with pinch-zoom, double-tap-to-zoom, and the three-way tap
/// zone navigation (left third / right third / center) used throughout the
/// reader. Reports zoom state so the parent can disable page-turn swipes
/// while zoomed in.
class ZoomablePage extends StatefulWidget {
  final Widget child;
  final VoidCallback onTapPrevious;
  final VoidCallback onTapNext;
  final VoidCallback onTapCenter;
  final ValueChanged<bool>? onZoomChanged;
  final bool tapZonesEnabled;

  const ZoomablePage({
    super.key,
    required this.child,
    required this.onTapPrevious,
    required this.onTapNext,
    required this.onTapCenter,
    this.onZoomChanged,
    this.tapZonesEnabled = true,
  });

  @override
  State<ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<ZoomablePage>
    with SingleTickerProviderStateMixin {
  final TransformationController _controller = TransformationController();
  late final AnimationController _animController;
  Animation<Matrix4>? _animation;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        if (_animation != null) _controller.value = _animation!.value;
      });
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _setZoomed(bool zoomed) {
    if (zoomed != _zoomed) {
      _zoomed = zoomed;
      widget.onZoomChanged?.call(zoomed);
    }
  }

  void _animateTo(Matrix4 target) {
    _animation = Matrix4Tween(begin: _controller.value, end: target)
        .animate(CurveTween(curve: Curves.easeOut).animate(_animController));
    _animController.forward(from: 0);
  }

  void _onDoubleTapDown(TapDownDetails details, Size size) {
    final isZoomed = _controller.value.getMaxScaleOnAxis() > 1.01;
    if (isZoomed) {
      _animateTo(Matrix4.identity());
      _setZoomed(false);
      return;
    }
    const scale = 2.5;
    final pos = details.localPosition;
    final x = -pos.dx * (scale - 1);
    final y = -pos.dy * (scale - 1);
    _animateTo(Matrix4.identity()
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1));
    _setZoomed(true);
  }

  void _onTapUp(TapUpDetails details, Size size) {
    if (_controller.value.getMaxScaleOnAxis() > 1.01) return;
    if (!widget.tapZonesEnabled) {
      widget.onTapCenter();
      return;
    }
    final dx = details.localPosition.dx;
    if (dx < size.width / 3) {
      widget.onTapPrevious();
    } else if (dx > size.width * 2 / 3) {
      widget.onTapNext();
    } else {
      widget.onTapCenter();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _onTapUp(d, size),
          onDoubleTapDown: (d) => _onDoubleTapDown(d, size),
          onDoubleTap: () {},
          child: InteractiveViewer(
            transformationController: _controller,
            minScale: 1,
            maxScale: 4,
            onInteractionEnd: (_) {
              _setZoomed(_controller.value.getMaxScaleOnAxis() > 1.01);
            },
            child: widget.child,
          ),
        );
      },
    );
  }
}
