import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';
import '../../../core/backend/models.dart';

/// Desktop/tablet chapter navigator. It slides over the right edge of the
/// reader (a transform, so the page underneath never re-lays-out) and jumps
/// straight to a chapter on click. Phones keep the bottom sheet, which also
/// has bulk actions.
class ChapterPanel extends StatefulWidget {
  final String title;
  final List<Book> books;
  final String currentId;
  final ValueChanged<Book> onOpen;
  final VoidCallback onClose;

  const ChapterPanel({
    super.key,
    required this.title,
    required this.books,
    required this.currentId,
    required this.onOpen,
    required this.onClose,
  });

  static const width = 320.0;
  static const _rowHeight = 56.0;

  @override
  State<ChapterPanel> createState() => _ChapterPanelState();
}

class _ChapterPanelState extends State<ChapterPanel> {
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    // Open with the current chapter a little below the top, not at the edge.
    final i = widget.books.indexWhere((b) => b.id == widget.currentId);
    final offset = ((i < 0 ? 0 : i) * ChapterPanel._rowHeight - 120).clamp(0.0, double.infinity);
    _scroll = ScrollController(initialScrollOffset: offset);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.canvas.withValues(alpha: 0.96),
      elevation: 16,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: AppColors.borderStrong)),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 8),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CHAPTERS', style: AppText.mono(size: 9.5)),
                        const SizedBox(height: 3),
                        Text(widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body(size: 15, weight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close (C)',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ]),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  itemExtent: ChapterPanel._rowHeight,
                  itemCount: widget.books.length,
                  itemBuilder: (context, i) {
                    final b = widget.books[i];
                    final current = b.id == widget.currentId;
                    return InkWell(
                      hoverColor: AppColors.fillHover,
                      onTap: current ? null : () => widget.onOpen(b),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        color: current ? AppColors.accent.withValues(alpha: 0.14) : null,
                        child: Row(children: [
                          SizedBox(
                            width: 22,
                            child: current
                                ? Icon(Icons.play_arrow_rounded, size: 18, color: AppColors.accent)
                                : b.completed
                                    ? Icon(Icons.check_rounded, size: 16, color: AppColors.text30)
                                    : null,
                          ),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(b.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.body(
                                      size: 14,
                                      color: b.completed && !current
                                          ? AppColors.text45
                                          : AppColors.text,
                                    )),
                                const SizedBox(height: 3),
                                Text('CH ${b.number}', style: AppText.mono(size: 9.5)),
                              ],
                            ),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
