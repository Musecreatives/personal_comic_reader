import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../backends/suwayomi/suwayomi_backend.dart';
import '../../core/backend/models.dart';
import '../collections/migrate_sheet.dart';
import '../shared/app_sheet.dart';
import '../shared/error_state.dart';
import '../shared/ink_chip.dart';
import '../suwayomi/sources_screen.dart' show HairlinePanel, SectionLabel;

/// A Suwayomi series' sources: the main one and its backups, which the
/// reader falls back to when the main source can't load a chapter. The
/// owner adds, removes and promotes backups; friends see the list. Returns
/// the new series id when a backup was made the main source.
Future<String?> showLinkedSourcesSheet(
  BuildContext context, {
  required SuwayomiBackend backend,
  required Series series,
  required bool canEdit,
}) {
  return showAppSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: Motion.sheetStyle,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => _LinkedSourcesSheet(backend: backend, series: series, canEdit: canEdit),
  );
}

class _LinkedSourcesSheet extends StatefulWidget {
  final SuwayomiBackend backend;
  final Series series;
  final bool canEdit;
  const _LinkedSourcesSheet(
      {required this.backend, required this.series, required this.canEdit});

  @override
  State<_LinkedSourcesSheet> createState() => _LinkedSourcesSheetState();
}

class _LinkedSourcesSheetState extends State<_LinkedSourcesSheet> {
  late Future<List<SourceCopy>> _copies = widget.backend.sourceCopies(widget.series.id);
  String? _busy;

  void _reload() =>
      setState(() => _copies = widget.backend.sourceCopies(widget.series.id));

  Future<void> _run(String label, Future<void> Function() action) async {
    setState(() => _busy = label);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppErrorState.errorHeadline(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _add() async {
    final linked = await showMigrateSheet(context, widget.backend, widget.series, link: true);
    if (linked != null && mounted) _reload();
  }

  Future<void> _remove(SourceCopy copy) =>
      _run('Removing…', () async {
        await widget.backend.unlinkSource(widget.series.id, copy.id);
        if (mounted) _reload();
      });

  Future<void> _makeMain(SourceCopy copy) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Make this the main source?'),
        content: Text(
            '"${widget.series.title}" moves to ${copy.source}. Chapters you\'ve '
            'read stay read, its categories come along, and the current source '
            'becomes the first backup.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Make main')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run('Switching…', () async {
      final id = await widget.backend.makeMain(widget.series.id, copy.id);
      if (mounted) Navigator.pop(context, id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetGrabber(),
              Text('Sources', style: AppText.heading(size: 18)),
              const SizedBox(height: 4),
              Text(
                "When the main source can't load a chapter, the same chapter is "
                'read from the first backup that has it.',
                style: AppText.body(size: 13, color: AppColors.text60),
              ),
              const SizedBox(height: 16),
              FutureBuilder<List<SourceCopy>>(
                future: _copies,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Text(AppErrorState.errorHeadline(snap.error!),
                        style: AppText.body(color: AppColors.dangerText));
                  }
                  final copies = snap.data;
                  if (copies == null) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator.adaptive()),
                    );
                  }
                  final backups = copies.skip(1).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel('MAIN'),
                      HairlinePanel(children: [_SourceRow(copy: copies.first)]),
                      const SizedBox(height: 16),
                      SectionLabel('BACKUPS · ${backups.length}'),
                      if (backups.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            widget.canEdit
                                ? 'No backups yet. Add the same title from another source.'
                                : 'No backups yet.',
                            style: AppText.body(size: 13, color: AppColors.text45),
                          ),
                        )
                      else
                        HairlinePanel(children: [
                          for (final (i, b) in backups.indexed)
                            _SourceRow(
                              copy: b,
                              order: i + 1,
                              onMakeMain: widget.canEdit && b.chapters > 0
                                  ? () => _makeMain(b)
                                  : null,
                              onRemove: widget.canEdit ? () => _remove(b) : null,
                            ),
                        ]),
                      if (widget.canEdit) ...[
                        const SizedBox(height: 18),
                        InkButton(
                          icon: Icons.add_link_rounded,
                          label: 'Add a backup source',
                          height: 44,
                          onTap: _busy == null ? _add : null,
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        if (_busy != null)
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.card.withValues(alpha: 0.8),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator.adaptive(),
                  const SizedBox(height: 12),
                  Text(_busy!, style: AppText.body(color: AppColors.text60)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final SourceCopy copy;
  final int? order;
  final VoidCallback? onMakeMain;
  final VoidCallback? onRemove;
  const _SourceRow({required this.copy, this.order, this.onMakeMain, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final facts = [
      '${copy.chapters} CH',
      if (copy.newest != null) 'NEWEST ${copy.newest!.toUpperCase()}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        if (order != null)
          SizedBox(
            width: 22,
            child: Text('$order', style: AppText.mono(size: 12, color: AppColors.text60)),
          ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(copy.source,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(size: 14.5, weight: FontWeight.w600)),
            if (copy.title.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(copy.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(size: 12, color: AppColors.text60)),
            ],
            const SizedBox(height: 3),
            Text(facts, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.mono(size: 10)),
          ]),
        ),
        if (onMakeMain != null)
          IconButton(
            tooltip: 'Make main',
            icon: Icon(Icons.vertical_align_top_rounded, color: AppColors.text),
            onPressed: onMakeMain,
          ),
        if (onRemove != null)
          IconButton(
            tooltip: 'Remove backup',
            icon: Icon(Icons.link_off_rounded, color: AppColors.text60),
            onPressed: onRemove,
          ),
      ]),
    );
  }
}
