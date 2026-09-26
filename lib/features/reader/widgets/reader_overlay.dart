import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';
import '../../../app/motion.dart';
import '../../../core/reader/reader_settings.dart';

/// Reader chrome, kept out of the way of the page: a slim glass pill at the
/// top (chapter + close), a vertical page scrubber down the right edge with
/// round glass buttons under it, and a faint "12 of 132" at the bottom that
/// stays visible even when the rest is hidden. Everything slides and fades
/// in together in a short stagger, and leaves faster than it arrived.
class ReaderOverlay extends StatefulWidget {
  final bool visible;
  final String title;
  final String subtitle;
  final int currentPage;
  final int pageCount;
  final ReaderSettings settings;
  final ValueChanged<int> onSeek;
  final VoidCallback onClose;
  final VoidCallback onOpenSettings;
  final VoidCallback onToggleDirection;
  final VoidCallback onCycleMode;
  final VoidCallback onOpenChapters;
  final VoidCallback? onTogglePanelMode;

  const ReaderOverlay({
    super.key,
    required this.visible,
    required this.title,
    required this.subtitle,
    required this.currentPage,
    required this.pageCount,
    required this.settings,
    required this.onSeek,
    required this.onClose,
    required this.onOpenSettings,
    required this.onToggleDirection,
    required this.onCycleMode,
    required this.onOpenChapters,
    this.onTogglePanelMode,
  });

  @override
  State<ReaderOverlay> createState() => _ReaderOverlayState();
}

class _ReaderOverlayState extends State<ReaderOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.base,
    reverseDuration: Motion.fast,
    value: widget.visible ? 1 : 0,
  );

  @override
  void didUpdateWidget(ReaderOverlay old) {
    super.didUpdateWidget(old);
    if (old.visible == widget.visible) return;
    if (Motion.reduced(context)) {
      _c.value = widget.visible ? 1 : 0;
    } else {
      widget.visible ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Animation<double> _part(double from, double to) => CurvedAnimation(
        parent: _c,
        curve: Interval(from, to, curve: Motion.easeOut),
      );

  /// Fades [child] in while it travels in from an offset.
  Widget _fx(Animation<double> a, Widget child, {double dx = 0, double dy = 0}) {
    return AnimatedBuilder(
      animation: a,
      child: child,
      builder: (context, c) => Opacity(
        opacity: a.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(dx * (1 - a.value), dy * (1 - a.value)),
          child: c,
        ),
      ),
    );
  }

  IconData _modeIcon(ReaderMode mode) => switch (mode) {
        ReaderMode.single => Icons.crop_portrait_rounded,
        ReaderMode.double => Icons.auto_stories_rounded,
        ReaderMode.verticalContinuous => Icons.view_agenda_rounded,
      };

  String _modeLabel(ReaderMode mode) => switch (mode) {
        ReaderMode.single => 'Paged',
        ReaderMode.double => 'Double page',
        ReaderMode.verticalContinuous => 'Webtoon',
      };

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final height = MediaQuery.sizeOf(context).height;
    final scrubberHeight = (height * 0.28).clamp(120.0, 240.0);
    final ltr = w.settings.direction == ReadingDirection.ltr;

    return Stack(
      children: [
        // Quiet page counter: shows when the chrome is hidden.
        Positioned(
          left: 0,
          right: 0,
          bottom: 10,
          child: SafeArea(
            top: false,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => Opacity(
                  opacity: 1 - _c.value,
                  child: Center(
                    child: Text(
                      '${w.currentPage + 1} of ${w.pageCount}',
                      style: AppText.mono(
                        size: 10.5,
                        color: Colors.white.withValues(alpha: 0.6),
                      ).copyWith(shadows: const [
                        Shadow(blurRadius: 6, color: Colors.black87),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _c,
          builder: (context, child) =>
              IgnorePointer(ignoring: _c.value < 0.05 && !w.visible, child: child),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                    child: _fx(
                      _part(0, 0.75),
                      _TopPill(
                        title: w.title,
                        subtitle: w.subtitle,
                        onClose: w.onClose,
                      ),
                      dy: -14,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: SafeArea(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _fx(
                          _part(0.1, 0.85),
                          _Scrubber(
                            height: scrubberHeight,
                            currentPage: w.currentPage,
                            pageCount: w.pageCount,
                            onSeek: w.onSeek,
                          ),
                          dx: 16,
                        ),
                        const SizedBox(height: 14),
                        _fx(
                          _part(0.2, 0.95),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _RoundButton(
                                icon: Icons.tune_rounded,
                                label: 'Reader settings',
                                onTap: w.onOpenSettings,
                              ),
                              const SizedBox(height: 10),
                              _RoundButton(
                                icon: Icons.format_list_bulleted_rounded,
                                label: 'Chapters',
                                onTap: w.onOpenChapters,
                              ),
                              const SizedBox(height: 10),
                              _RoundButton(
                                icon: _modeIcon(w.settings.mode),
                                label: 'Reading mode: ${_modeLabel(w.settings.mode)}',
                                onTap: w.onCycleMode,
                              ),
                              const SizedBox(height: 10),
                              _RoundButton(
                                icon: ltr
                                    ? Icons.format_textdirection_l_to_r
                                    : Icons.format_textdirection_r_to_l,
                                label: ltr ? 'Left to right' : 'Right to left',
                                onTap: w.onToggleDirection,
                              ),
                              if (w.onTogglePanelMode != null) ...[
                                const SizedBox(height: 10),
                                _RoundButton(
                                  icon: Icons.crop_free_rounded,
                                  label: 'Panel mode',
                                  onTap: w.onTogglePanelMode!,
                                ),
                              ],
                            ],
                          ),
                          dx: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopPill extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onClose;
  const _TopPill({required this.title, required this.subtitle, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return _Glass(
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 6, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(size: 15, weight: FontWeight.w600)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.mono(size: 10, color: AppColors.text60)),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Close reader',
              onPressed: onClose,
              icon: Icon(Icons.close_rounded, size: 22, color: AppColors.text),
            ),
          ],
        ),
      ),
    );
  }
}

/// The vertical page scrubber: a tall glass pill filled from the top in
/// proportion to how far through the chapter you are. Drag it or tap
/// anywhere on it to jump; the current page number sits at its top.
class _Scrubber extends StatelessWidget {
  final double height;
  final int currentPage;
  final int pageCount;
  final ValueChanged<int> onSeek;

  const _Scrubber({
    required this.height,
    required this.currentPage,
    required this.pageCount,
    required this.onSeek,
  });

  // Top is always the first page. (The old horizontal slider flipped for
  // right-to-left; a vertical bar reads top-to-bottom whatever the direction.)
  void _seekTo(double dy) {
    if (pageCount <= 1) return;
    final frac = (dy / height).clamp(0.0, 1.0);
    onSeek((frac * (pageCount - 1)).round());
  }

  @override
  Widget build(BuildContext context) {
    final frac =
        pageCount <= 1 ? 0.0 : (currentPage / (pageCount - 1)).clamp(0.0, 1.0);
    return Semantics(
      label: 'Page ${currentPage + 1} of $pageCount',
      slider: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _seekTo(d.localPosition.dy),
        onVerticalDragStart: (d) => _seekTo(d.localPosition.dy),
        onVerticalDragUpdate: (d) => _seekTo(d.localPosition.dy),
        child: _Glass(
          radius: 22,
          child: SizedBox(
            width: 44,
            height: height,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: FractionallySizedBox(
                    heightFactor: frac,
                    widthFactor: 1,
                    child: ColoredBox(color: AppColors.accent.withValues(alpha: 0.5)),
                  ),
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('${currentPage + 1}',
                        style: AppText.mono(
                            size: 11, weight: FontWeight.w600, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _RoundButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: PressScale(
        scale: 0.92,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: _Glass(
            radius: 22,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, size: 20, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  const _Glass({required this.child, required this.radius});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.canvas.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: AppColors.borderStrong.withValues(alpha: 0.8)),
          ),
          child: child,
        ),
      ),
    );
  }
}
