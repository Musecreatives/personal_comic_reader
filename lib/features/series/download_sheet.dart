import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../core/backend/models.dart';

/// What to download for a series: presets built from the reader's own state
/// (where you left off, what's unread, what's new since) plus a checklist.
/// Chapters already downloaded or queued are never offered again, and each
/// option shows how many chapters it would add.
class DownloadSheet extends StatefulWidget {
  /// Every chapter of the series, in reading order.
  final List<Book> books;

  /// Chapters already downloaded or in the queue.
  final Set<String> alreadyIds;
  final Future<void> Function(List<Book> chosen) onConfirm;

  const DownloadSheet({
    super.key,
    required this.books,
    required this.alreadyIds,
    required this.onConfirm,
  });

  static Future<void> show(
    BuildContext context, {
    required List<Book> books,
    required Set<String> alreadyIds,
    required Future<void> Function(List<Book>) onConfirm,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: Motion.sheetStyle,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => DownloadSheet(
        books: books,
        alreadyIds: alreadyIds,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  State<DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<DownloadSheet> {
  bool _choosing = false;
  final Set<String> _picked = {};

  String _label(Book b) {
    final n = b.number.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final t = b.title.trim();
    final same =
        t.isEmpty ||
        RegExp(
          '^(ch(apter)?\\.?\\s*)?0*${RegExp.escape(n)}(\\.0+)?\$',
          caseSensitive: false,
        ).hasMatch(t);
    return same ? 'Ch. $n' : 'Ch. $n  $t';
  }

  Future<void> _confirm(List<Book> chosen) async {
    Navigator.of(context).pop();
    await widget.onConfirm(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final books = widget.books;
    final todo = books.where((b) => !widget.alreadyIds.contains(b.id)).toList();
    final unread = todo.where((b) => !b.completed).toList();
    // Everything after the furthest chapter you have touched.
    final lastTouched = books.lastIndexWhere(
      (b) => b.completed || (b.readProgressPage ?? 0) > 0,
    );
    final ahead = unread.where((b) => books.indexOf(b) > lastTouched).toList();
    // "Next" starts at the chapter you are on, else at the first unread.
    final upNext = [
      ...unread.where(
        (b) => books.indexOf(b) >= (lastTouched < 0 ? 0 : lastTouched),
      ),
    ];
    final next = upNext.isNotEmpty ? upNext : unread;

    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: AnimatedSize(
          duration: Motion.scaled(context, Motion.base),
          curve: Motion.easeOut,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.text30,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  'Download to this device',
                  style: AppText.heading(size: 19),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  todo.isEmpty
                      ? 'Everything in this series is already downloaded or queued.'
                      : '${todo.length} chapters available',
                  style: AppText.body(size: 12.5, color: AppColors.text60),
                ),
              ),
              if (!_choosing) ...[
                _Option(
                  title: 'Next 5',
                  hint: 'From where you are',
                  chapters: next.take(5).toList(),
                  onTap: _confirm,
                ),
                _Option(
                  title: 'Next 10',
                  hint: 'From where you are',
                  chapters: next.take(10).toList(),
                  onTap: _confirm,
                ),
                _Option(
                  title: 'New since you last read',
                  hint: 'Unread chapters after your latest',
                  chapters: ahead,
                  onTap: _confirm,
                ),
                _Option(
                  title: 'All unread',
                  hint: 'Every chapter you have not finished',
                  chapters: unread,
                  onTap: _confirm,
                ),
                _Option(
                  title: 'Everything',
                  hint: 'Including chapters you have read',
                  chapters: todo,
                  onTap: _confirm,
                ),
                _Option(
                  title: 'Choose chapters',
                  hint: 'Pick exactly which ones',
                  chapters: todo,
                  chevron: true,
                  onTap: (_) => setState(() => _choosing = true),
                ),
                const SizedBox(height: 12),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _choosing = false),
                        child: const Text('Back'),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(
                          () => _picked
                            ..clear()
                            ..addAll(todo.map((b) => b.id)),
                        ),
                        child: const Text('Select all'),
                      ),
                      TextButton(
                        onPressed: () => setState(_picked.clear),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: todo.length,
                    itemBuilder: (context, i) {
                      final b = todo[i];
                      final on = _picked.contains(b.id);
                      return CheckboxListTile(
                        dense: true,
                        value: on,
                        activeColor: AppColors.accent,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          _label(b),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: b.completed
                            ? Text(
                                'Read',
                                style: AppText.mono(
                                  size: 10,
                                  color: AppColors.text45,
                                ),
                              )
                            : null,
                        onChanged: (v) => setState(() {
                          v == true ? _picked.add(b.id) : _picked.remove(b.id);
                        }),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _picked.isEmpty
                          ? null
                          : () => _confirm(
                              todo
                                  .where((b) => _picked.contains(b.id))
                                  .toList(),
                            ),
                      child: Text(
                        _picked.isEmpty
                            ? 'Select chapters'
                            : 'Download ${_picked.length}',
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final String title;
  final String hint;
  final List<Book> chapters;
  final bool chevron;
  final ValueChanged<List<Book>> onTap;
  const _Option({
    required this.title,
    required this.hint,
    required this.chapters,
    required this.onTap,
    this.chevron = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = chapters.isNotEmpty;
    return PressScale(
      scale: 0.985,
      child: InkWell(
        onTap: enabled ? () => onTap(chapters) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppText.body(size: 15, weight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        hint,
                        style: AppText.body(size: 12, color: AppColors.text45),
                      ),
                    ],
                  ),
                ),
                Text(
                  chevron ? '' : '${chapters.length}',
                  style: AppText.mono(size: 12, color: AppColors.accentLink),
                ),
                Icon(
                  chevron
                      ? Icons.chevron_right_rounded
                      : Icons.download_outlined,
                  size: 20,
                  color: AppColors.text45,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
