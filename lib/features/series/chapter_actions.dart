import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';

/// What can be done to one or many chapters. Shared by the series page's
/// selection bar and its right-click / long-press menu.
enum ChapterAction {
  markRead('Mark as read', Icons.check_rounded),
  markUnread('Mark as unread', Icons.remove_done_rounded),
  download('Download', Icons.download_outlined),
  deleteDownload('Remove download', Icons.delete_outline_rounded);

  final String label;
  final IconData icon;
  const ChapterAction(this.label, this.icon);
}

/// Opens the context menu at [position] (a pointer position in global
/// coordinates). Returns the chosen action, or null if dismissed.
Future<ChapterAction?> showChapterMenu(
  BuildContext context,
  Offset position, {
  required int count,
  required bool anyDownloaded,
}) {
  final size = MediaQuery.of(context).size;
  final actions = [
    for (final a in ChapterAction.values)
      if (a != ChapterAction.deleteDownload || anyDownloaded) a,
  ];
  return showMenu<ChapterAction>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      size.width - position.dx,
      size.height - position.dy,
    ),
    color: AppColors.card,
    elevation: 12,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(13),
      side: BorderSide(color: AppColors.borderStrong),
    ),
    items: [
      if (count > 1)
        PopupMenuItem<ChapterAction>(
          enabled: false,
          height: 30,
          child: Text('$count CHAPTERS', style: AppText.mono(size: 9.5)),
        ),
      for (final a in actions)
        PopupMenuItem<ChapterAction>(
          value: a,
          height: 40,
          child: Row(
            children: [
              Icon(
                a.icon,
                size: 17,
                color: a == ChapterAction.deleteDownload
                    ? Colors.redAccent
                    : AppColors.text60,
              ),
              const SizedBox(width: 12),
              Text(a.label, style: AppText.body(size: 14)),
            ],
          ),
        ),
    ],
  );
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
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
              constraints: const BoxConstraints(maxWidth: 560),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.borderStrong),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
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
                      style: AppText.body(size: 14, weight: FontWeight.w600),
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
                  for (final a in ChapterAction.values)
                    if (a != ChapterAction.deleteDownload || anyDownloaded)
                      IconButton(
                        tooltip: a.label,
                        onPressed: () => onAction(a),
                        icon: Icon(
                          a.icon,
                          size: 19,
                          color: a == ChapterAction.deleteDownload
                              ? Colors.redAccent
                              : AppColors.text,
                        ),
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
