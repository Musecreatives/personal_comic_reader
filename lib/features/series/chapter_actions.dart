import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../app/platform_style.dart';
import '../shared/glass_panel.dart';

/// What can be done to one or many chapters. Shared by the series page's
/// selection bar and its long-press / right-click menu.
enum ChapterAction {
  select('Select', Icons.check_circle_outline_rounded),
  markRead('Mark as read', Icons.check_rounded),
  markReadBefore(
    'Mark all before as read',
    Icons.done_all_rounded,
    hint: 'Also marks this chapter',
  ),
  markUnread('Mark as unread', Icons.remove_done_rounded),
  download('Download', Icons.download_outlined),
  deleteDownload('Remove download', Icons.delete_outline_rounded);

  final String label;
  final IconData icon;
  final String? hint;
  const ChapterAction(this.label, this.icon, {this.hint});

  bool get destructive => this == deleteDownload;

  /// What the bulk selection bar offers; the rest only make sense for the
  /// one chapter a menu was opened on.
  static const bulk = [markRead, markUnread, download, deleteDownload];
}

/// Opens the chapter menu next to [position] (global coordinates, where the
/// finger or pointer was). [heading] names what it acts on. Returns the
/// chosen action, or null if dismissed.
Future<ChapterAction?> showChapterMenu(
  BuildContext context,
  Offset position, {
  required List<ChapterAction> actions,
  String? heading,
}) {
  return showGeneralDialog<ChapterAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close menu',
    // iOS dims what's behind a context menu a little; elsewhere the menu
    // just floats.
    barrierColor: PlatformStyle.isIOS
        ? Colors.black.withValues(alpha: 0.18)
        : Colors.transparent,
    transitionDuration: Motion.scaled(context, Motion.fast),
    pageBuilder: (context, _, _) => CustomSingleChildLayout(
      delegate: _MenuLayout(position, MediaQuery.paddingOf(context)),
      child: _ChapterMenu(actions: actions, heading: heading),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Motion.easeOut);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(curved),
          alignment: Alignment.topLeft,
          child: child,
        ),
      );
    },
  );
}

/// Puts the menu beside the press point and keeps it on screen: it opens
/// downward and rightward, and flips up or left when there is no room.
class _MenuLayout extends SingleChildLayoutDelegate {
  final Offset at;
  final EdgeInsets padding;
  const _MenuLayout(this.at, this.padding);

  static const _margin = 12.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) => BoxConstraints(
    maxWidth: (c.maxWidth - _margin * 2).clamp(0, 300),
    maxHeight: c.maxHeight - padding.vertical - _margin * 2,
  );

  @override
  Offset getPositionForChild(Size size, Size child) {
    final x = at.dx + child.width + _margin <= size.width
        ? at.dx
        : at.dx - child.width;
    final y = at.dy + child.height + padding.bottom + _margin <= size.height
        ? at.dy
        : at.dy - child.height;
    return Offset(
      x.clamp(_margin, size.width - child.width - _margin),
      y.clamp(padding.top + _margin, size.height - child.height - _margin),
    );
  }

  @override
  bool shouldRelayout(_MenuLayout old) =>
      old.at != at || old.padding != padding;
}

class _ChapterMenu extends StatelessWidget {
  final List<ChapterAction> actions;
  final String? heading;
  const _ChapterMenu({required this.actions, this.heading});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: IntrinsicWidth(
        stepWidth: 40,
        child: GlassPanel(
          radius: PlatformStyle.isIOS ? 14 : 16,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (heading != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    child: Text(
                      heading!,
                      style: AppText.mono(size: 10.5, color: AppColors.text60),
                    ),
                  ),
                for (final a in actions) ...[
                  // Destructive actions sit apart, below a hairline.
                  if (a.destructive && actions.length > 1)
                    Divider(height: 9, color: AppColors.border),
                  _MenuItem(action: a),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final ChapterAction action;
  const _MenuItem({required this.action});

  @override
  Widget build(BuildContext context) {
    final color = action.destructive ? AppColors.dangerText : AppColors.text;
    return InkWell(
      onTap: () => Navigator.of(context).pop(action),
      hoverColor: AppColors.fillHover,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 20, 10),
          child: Row(
            children: [
              Icon(action.icon, size: 20, color: color),
              const SizedBox(width: 14),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.label,
                      style: AppText.body(size: 15, color: color),
                    ),
                    if (action.hint != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        action.hint!,
                        style: AppText.body(
                          size: 12.5,
                          color: AppColors.text60,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bar that rises from the bottom while chapters are selected. It arrives
/// with an ease-out and leaves faster than it came (the user is done, get
/// out of the way).
class ChapterSelectionBar extends StatelessWidget {
  final int count;
  final int total;
  final bool anyDownloaded;
  final ValueChanged<ChapterAction> onAction;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;

  const ChapterSelectionBar({
    super.key,
    required this.count,
    required this.total,
    required this.anyDownloaded,
    required this.onAction,
    required this.onSelectAll,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final showing = count > 0;
    final d = Motion.scaled(context, showing ? Motion.base : Motion.press);
    return IgnorePointer(
      ignoring: !showing,
      child: AnimatedSlide(
        offset: showing ? Offset.zero : const Offset(0, 1.2),
        duration: d,
        curve: Motion.easeOut,
        child: AnimatedOpacity(
          opacity: showing ? 1 : 0,
          duration: d,
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              constraints: const BoxConstraints(maxWidth: 560),
              child: GlassPanel(
                radius: 20,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Clear selection (Esc)',
                        onPressed: onClear,
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                      Expanded(
                        child: Text(
                          '$count selected',
                          style: AppText.body(
                            size: 14,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (count < total)
                        TextButton(
                          onPressed: onSelectAll,
                          child: Text(
                            'All',
                            style: AppText.body(
                              size: 13,
                              color: AppColors.accentLink,
                            ),
                          ),
                        ),
                      for (final a in ChapterAction.bulk)
                        if (a != ChapterAction.deleteDownload || anyDownloaded)
                          IconButton(
                            tooltip: a.label,
                            onPressed: () => onAction(a),
                            icon: Icon(
                              a.icon,
                              size: 19,
                              color: a.destructive
                                  ? AppColors.dangerText
                                  : AppColors.text,
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
