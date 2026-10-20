import 'package:flutter/material.dart';

/// Shared motion language. Keep UI motion under ~300ms, ease-out for things
/// entering, ease-in-out for things moving on screen, and never animate
/// high-frequency actions (keyboard shortcuts, page turns in the reader).
/// Curves are stronger than Flutter's built-ins on purpose: they front-load
/// the movement so the interface feels like it answered instantly.
class Motion {
  Motion._();

  /// Entrances and most UI feedback.
  static const easeOut = Cubic(0.23, 1, 0.32, 1);

  /// Things already on screen moving or morphing.
  static const easeInOut = Cubic(0.77, 0, 0.175, 1);

  /// iOS-like sheet/drawer curve.
  static const drawer = Cubic(0.32, 0.72, 0, 1);

  static const press = Duration(milliseconds: 120);
  static const fast = Duration(milliseconds: 180);
  static const base = Duration(milliseconds: 260);
  static const sheet = Duration(milliseconds: 340);

  /// Bottom sheets: a confident ease-out rise, a quicker exit.
  static final sheetStyle = AnimationStyle(
    duration: sheet,
    curve: drawer,
    reverseDuration: base,
    reverseCurve: easeOut,
  );

  /// Respect the system "reduce motion" setting: keep state changes, drop
  /// the movement.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration scaled(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}

/// Presses in slightly while a finger/pointer is down, so a control feels
/// like it heard the touch. Wraps a control without intercepting its tap.
class PressScale extends StatefulWidget {
  final Widget child;
  final double scale;
  const PressScale({super.key, required this.child, this.scale = 0.97});

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Motion.scaled(context, Motion.press),
        curve: Motion.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Fades and lifts [child] in when it first appears. [delay] staggers a
/// list of siblings (30-60ms apart reads as a cascade; longer feels slow).
class FadeSlideIn extends StatelessWidget {
  final Widget child;
  final Duration delay;
  final double dy;
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.dy = 10,
  });

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return child;
    final total = Motion.base + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(
        delay.inMilliseconds / total.inMilliseconds,
        1,
        curve: Motion.easeOut,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, dy * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}
