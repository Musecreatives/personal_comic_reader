import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'design_tokens.dart';
import 'motion.dart';

/// The logo mark: a hanko-red square stamped with 読 (DESIGN.md "Seal").
/// Tilted 4° from 48px up; smaller seals sit straight.
class BrandSeal extends StatelessWidget {
  const BrandSeal({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    final seal = Container(
      width: size,
      height: size,
      color: AppColors.seal,
      alignment: Alignment.center,
      child: Text('読',
          style: GoogleFonts.delaGothicOne(
              fontSize: size * 0.62, height: 1, color: AppColors.onSeal)),
    );
    return Semantics(
      label: 'Shaddai Reader',
      image: true,
      child: ExcludeSemantics(
        child: size >= 48 ? Transform.rotate(angle: -4 * math.pi / 180, child: seal) : seal,
      ),
    );
  }
}

/// An empty screen (DESIGN.md "Empty states"): a 2px-framed block on
/// screentone, 空 in hanko red, a heading, one line of help and [action].
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.message, this.action});

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.text, width: 2),
            ),
            child: CustomPaint(
              painter: Screentone(AppColors.text.withValues(alpha: 0.12)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ExcludeSemantics(
                    child: Text('空',
                        style: GoogleFonts.delaGothicOne(
                            fontSize: 64, height: 1, color: AppColors.sealText)),
                  ),
                  const SizedBox(height: 16),
                  Text(title, textAlign: TextAlign.center, style: AppText.heading(size: 18)),
                  const SizedBox(height: 6),
                  Text(message,
                      textAlign: TextAlign.center,
                      style: AppText.body(size: 13, color: AppColors.text60)),
                  if (action != null) ...[const SizedBox(height: 18), action!],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 1.2px dots on an 8px grid (DESIGN.md "Screentone").
class Screentone extends CustomPainter {
  Screentone(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (var y = 4.0; y < size.height; y += 8) {
      for (var x = 4.0; x < size.width; x += 8) {
        canvas.drawCircle(Offset(x, y), 1.2, p);
      }
    }
  }

  @override
  bool shouldRepaint(Screentone old) => old.color != color;
}

/// Plays the logo once per launch over [child] (DESIGN.md "Logo motion"):
/// three panels ink in, right first, each naming the app in its script, then
/// close into one seal that presses 読 as "Shaddai Reader" lands. 2.4s, then
/// fades away. With reduced motion it is skipped.
class LaunchSplash extends StatefulWidget {
  const LaunchSplash({super.key, required this.child});

  final Widget child;

  // The app subtree is rebuilt under a new key on every appearance change,
  // so the clock lives here: a rebuilt splash picks up where the last left
  // off, and one rebuilt after the 2.7s never shows.
  static DateTime? _start;

  @override
  State<LaunchSplash> createState() => _LaunchSplashState();
}

class _LaunchSplashState extends State<LaunchSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2700));
  bool _show = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_show || _c.isAnimating) return;
    final start = LaunchSplash._start ??= DateTime.now();
    final from = DateTime.now().difference(start).inMilliseconds / 2700;
    if (from >= 1 || Motion.reduced(context)) {
      _show = false;
      return;
    }
    _c.forward(from: from).whenComplete(() {
      if (mounted) setState(() => _show = false);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // Eased 0..1 progress between [a] and [b] milliseconds on the 2.7s clock.
  double _at(double a, double b) =>
      Curves.easeOutCubic.transform(((_c.value * 2700 - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    if (!_show) return widget.child;
    return Stack(children: [
      widget.child,
      Positioned.fill(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Opacity(
            opacity: 1 - _at(2400, 2700),
            child: ColoredBox(
              color: AppColors.page,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                _mark(),
                const SizedBox(height: 30),
                SizedBox(height: 46, child: _wordmark()),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _mark() {
    const s = 136.0;
    final ink = AppColors.text;
    final closed = _at(720, 1020); // gutters close into one seal
    final press = _at(1020, 1400); // 読 presses in
    Widget panel(double from, Widget child) => Opacity(
          opacity: _at(from, from + 240) * (1 - closed),
          child: child,
        );
    Widget outlined(String g, TextStyle style, double size) => Container(
          decoration: BoxDecoration(border: Border.all(color: ink, width: 3)),
          alignment: Alignment.center,
          child: Text(g, style: style.copyWith(fontSize: size, height: 1, color: ink)),
        );
    return Transform.rotate(
      angle: -4 * math.pi / 180 * closed,
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(children: [
          // Right panel: the seal's first half, 読 in Japanese.
          Positioned(
            left: s * 0.52, right: 0, top: 0, bottom: 0,
            child: panel(0, Container(
              color: AppColors.seal,
              alignment: Alignment.center,
              child: Text('読',
                  style: GoogleFonts.delaGothicOne(fontSize: s * 0.3, color: AppColors.onSeal)),
            )),
          ),
          Positioned(
            left: 0, top: 0, width: s * 0.48, height: s * 0.48,
            child: panel(240, outlined('읽', GoogleFonts.blackHanSans(), s * 0.24)),
          ),
          Positioned(
            left: 0, bottom: 0, width: s * 0.48, height: s * 0.48,
            child: panel(480, outlined('读', GoogleFonts.maShanZheng(), s * 0.28)),
          ),
          // The closed seal, pressing 読 (scale 1.7 to 1, a 12° turn).
          Opacity(
            opacity: closed,
            child: Container(
              color: AppColors.seal,
              alignment: Alignment.center,
              child: Opacity(
                opacity: press,
                child: Transform.rotate(
                  angle: -12 * math.pi / 180 * (1 - press),
                  child: Transform.scale(
                    scale: 1.7 - 0.7 * press,
                    child: Text('読',
                        style: GoogleFonts.delaGothicOne(
                            fontSize: s * 0.62, height: 1, color: AppColors.onSeal)),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _wordmark() {
    final ms = _c.value * 2700;
    final (text, style) = ms < 240
        ? ('シャダイ リーダー', GoogleFonts.delaGothicOne(fontSize: 29))
        : ms < 480
            ? ('샤다이 리더', GoogleFonts.blackHanSans(fontSize: 35))
            : ms < 1400
                ? ('沙代阅读', GoogleFonts.maShanZheng(fontSize: 40))
                : ('Shaddai Reader',
                    GoogleFonts.zenKakuGothicNew(
                        fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1.2));
    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: Text(text, key: ValueKey(text), style: style.copyWith(color: AppColors.text)),
      ),
    );
  }
}
