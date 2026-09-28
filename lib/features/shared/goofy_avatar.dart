import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';

/// The desktop side rail's mascot: a purple blob with googly eyes that roll
/// around, a blink, a wobbling tongue and a squishy bob. Tap it to boing.
/// Plays in bursts with rests between, so an idle app isn't redrawing every
/// frame forever. Holds still under the system "reduce motion" setting.
class GoofyAvatar extends StatefulWidget {
  final double size;
  const GoofyAvatar({super.key, this.size = 38});

  @override
  State<GoofyAvatar> createState() => _GoofyAvatarState();
}

class _GoofyAvatarState extends State<GoofyAvatar>
    with TickerProviderStateMixin {
  late final _idle =
      AnimationController(vsync: this, duration: const Duration(seconds: 4));
  late final _boing = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));
  Timer? _rest;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _idle.addStatusListener((status) {
      if (status != AnimationStatus.completed || _reduced) return;
      _rest = Timer(const Duration(seconds: 6), _play);
    });
  }

  void _play() {
    if (mounted && !_reduced) _idle.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = Motion.reduced(context);
    if (reduced == _reduced && (_idle.isAnimating || _rest != null)) return;
    _reduced = reduced;
    _rest?.cancel();
    _rest = null;
    if (reduced) {
      _idle.stop();
    } else {
      _play();
    }
  }

  @override
  void dispose() {
    _rest?.cancel();
    _idle.dispose();
    _boing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Shaddai Reader mascot',
      button: true,
      child: GestureDetector(
        onTap: Motion.reduced(context) ? null : () => _boing.forward(from: 0),
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _BlobPainter(
              idle: _idle,
              boing: _boing,
              body: AppColors.accent,
              shade: AppColors.accentSoft,
            ),
          ),
        ),
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  final Animation<double> idle;
  final Animation<double> boing;
  final Color body;
  final Color shade;

  _BlobPainter({
    required this.idle,
    required this.boing,
    required this.body,
    required this.shade,
  }) : super(repaint: Listenable.merge([idle, boing]));

  @override
  void paint(Canvas canvas, Size size) {
    final t = idle.value; // 0..1 over 4s
    final w = size.width;
    final turn = t * 2 * math.pi;

    // Boing: a decaying wobble, big squash first then settling.
    final b = boing.value;
    final wobble = b == 0 ? 0.0 : math.sin(b * math.pi * 5) * (1 - b) * 0.22;
    // Idle breathing bob.
    final bob = math.sin(turn * 2) * 0.035;
    final sx = 1 + wobble + bob;
    final sy = 1 - wobble - bob;

    canvas.save();
    // Squash from the bottom so it looks like it's sitting on the rail.
    canvas.translate(w / 2, w * 0.95);
    canvas.scale(sx, sy);
    canvas.rotate(math.sin(turn) * 0.06);
    canvas.translate(-w / 2, -w * 0.95);

    // Body: a slightly lumpy blob, lumps drifting with time.
    final center = Offset(w / 2, w * 0.54);
    final r = w * 0.44;
    final path = Path();
    const steps = 36;
    for (var i = 0; i <= steps; i++) {
      final a = i / steps * 2 * math.pi;
      final lump =
          1 + 0.045 * math.sin(a * 3 + turn) + 0.03 * math.sin(a * 5 - turn * 2);
      final p = center + Offset(math.cos(a), math.sin(a) * 0.92) * r * lump;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 0.9,
          colors: [shade, body],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // Tongue, wagging side to side.
    final tongueX = center.dx + w * 0.06 + math.sin(turn * 3) * w * 0.03;
    final tongue = Rect.fromCenter(
        center: Offset(tongueX, center.dy + r * 0.52),
        width: w * 0.16,
        height: w * 0.2);
    canvas.drawRRect(
      RRect.fromRectAndCorners(tongue,
          bottomLeft: Radius.circular(w * 0.08),
          bottomRight: Radius.circular(w * 0.08)),
      Paint()..color = const Color(0xFFFF6B9A),
    );

    // Mouth: a lopsided grin over the tongue.
    final mouth = Path()
      ..moveTo(center.dx - r * 0.42, center.dy + r * 0.3)
      ..quadraticBezierTo(center.dx, center.dy + r * 0.62,
          center.dx + r * 0.46, center.dy + r * 0.22);
    canvas.drawPath(
      mouth,
      Paint()
        ..color = const Color(0xFF1B1030)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.055
        ..strokeCap = StrokeCap.round,
    );

    // Googly eyes: mismatched sizes, pupils rolling out of sync. A blink
    // squashes both shut briefly once per loop.
    final blink =
        (t > 0.62 && t < 0.67) ? math.sin((t - 0.62) / 0.05 * math.pi) : 0.0;
    _eye(canvas, center + Offset(-r * 0.36, -r * 0.22), w * 0.15, turn, blink);
    _eye(canvas, center + Offset(r * 0.34, -r * 0.3), w * 0.19,
        -turn * 1.3 + 1, blink);

    canvas.restore();
  }

  void _eye(Canvas canvas, Offset c, double r, double angle, double blink) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1, 1 - blink * 0.9);
    canvas.drawCircle(Offset.zero, r, Paint()..color = Colors.white);
    final pupil = Offset(math.cos(angle), math.sin(angle)) * r * 0.42;
    canvas.drawCircle(pupil, r * 0.5, Paint()..color = const Color(0xFF1B1030));
    canvas.drawCircle(pupil + Offset(-r * 0.15, -r * 0.18), r * 0.14,
        Paint()..color = Colors.white);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BlobPainter old) =>
      old.body != body || old.shade != shade;
}
