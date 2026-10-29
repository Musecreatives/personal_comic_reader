import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';

/// The ink action button (the design system "Buttons"). [filled] is the primary:
/// ink fill, page-coloured label, 2px ink edge and the violet offset shadow,
/// which lifts 2px on hover and is pressed into on tap, like a seal. The
/// outline form is an ink edge with an ink label. Movement is dropped
/// under reduced motion; the colour states remain.
class InkButton extends StatefulWidget {
  const InkButton({
    super.key,
    this.icon,
    this.label,
    required this.onTap,
    this.filled = false,
    this.height = 48,
  });

  final IconData? icon;
  final String? label;
  final VoidCallback? onTap;
  final bool filled;
  final double height;

  @override
  State<InkButton> createState() => _InkButtonState();
}

class _InkButtonState extends State<InkButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final still = Motion.reduced(context);
    final enabled = w.onTap != null;
    // Offset of the face and of the shadow, per state.
    final lift = !enabled || still ? 0.0 : (_down ? 3.0 : (_hover ? -2.0 : 0.0));
    final shadow = !w.filled ? 0.0 : (_down && !still ? 2.0 : (_hover && !still ? 7.0 : 5.0));
    final fg = w.filled ? AppColors.page : AppColors.text;
    final radius = BorderRadius.circular(20);
    final iconOnly = w.label == null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: w.label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: w.onTap,
          child: AnimatedContainer(
            duration: Motion.scaled(context, Motion.press),
            curve: Motion.easeOut,
            height: w.height,
            width: iconOnly ? w.height : null,
            padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 20),
            transform: Matrix4.translationValues(lift, lift, 0),
            decoration: BoxDecoration(
              color: w.filled
                  ? AppColors.text
                  : (_hover || _down ? AppColors.fillHover : Colors.transparent),
              borderRadius: radius,
              border: Border.all(color: AppColors.text, width: 2),
              boxShadow: w.filled
                  ? [BoxShadow(color: AppColors.accent, offset: Offset(shadow, shadow))]
                  : null,
            ),
            child: Opacity(
              opacity: enabled ? 1 : 0.5,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (w.icon != null) Icon(w.icon, size: iconOnly ? 20 : 18, color: fg),
                  if (w.icon != null && !iconOnly) const SizedBox(width: 8),
                  if (!iconOnly)
                    Flexible(
                      child: Text(w.label!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(size: 15, weight: FontWeight.w700, color: fg)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The one filter chip (the design system: a 2px control line, pill corners).
/// Unselected chips are drawn in ink, not filled; the selected one takes the
/// accent, because the accent is what you have picked. [secondary] marks a
/// second kind of choice (a collection beside All / Unread) with an accent
/// outline instead of a fill. [dot] names a source in its own colour.
class InkChip extends StatelessWidget {
  const InkChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dot,
    this.icon,
    this.secondary = false,
    this.dimmed = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dot;
  final IconData? icon;
  final bool secondary;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final filled = selected && !secondary;
    final ink = filled
        ? Colors.white
        : selected
            ? AppColors.accentLink
            : AppColors.text;
    return Semantics(
      button: true,
      selected: selected,
      child: PressScale(
        child: Opacity(
          opacity: dimmed && !selected ? 0.55 : 1,
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: Motion.scaled(context, Motion.fast),
              curve: Motion.easeOut,
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: filled ? AppColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  width: 2,
                  color: selected
                      ? AppColors.accent
                      : AppColors.text.withValues(alpha: 0.62),
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: ink),
                  const SizedBox(width: 6),
                ] else if (dot != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                      border: filled ? Border.all(color: Colors.white, width: 1.5) : null,
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
                Text(label,
                    style: AppText.body(size: 12.5, weight: FontWeight.w600, color: ink)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
