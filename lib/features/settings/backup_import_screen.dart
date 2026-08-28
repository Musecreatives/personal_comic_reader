import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../backends/suwayomi/suwayomi_backend.dart';
import '../../core/backup_import/backup_import_controller.dart';
import '../../core/backup_import/paperback_backup.dart';
import '../shared/error_state.dart';

enum _Step { pickFile, matching, review, applying, done }

/// Paperback `.pas5` backup import (6f). Only meaningful against a
/// Suwayomi server - Paperback's model is "a scraper site + a chapter
/// list," which only Suwayomi's source system has an equivalent for.
/// Dry-run by default: matching never writes anything; Apply is a
/// separate, explicit step over whatever you haven't excluded.
class BackupImportScreen extends ConsumerStatefulWidget {
  const BackupImportScreen({super.key});

  @override
  ConsumerState<BackupImportScreen> createState() => _BackupImportScreenState();
}

class _BackupImportScreenState extends ConsumerState<BackupImportScreen> {
  _Step _step = _Step.pickFile;
  String? _error;

  PaperbackBackup? _backup;
  final List<TitleMatch> _matches = [];
  int _matchDone = 0;
  int _matchTotal = 0;

  int _applyDone = 0;
  int _applyTotal = 0;
  final List<String> _applyErrors = [];

  Future<void> _pickFile() async {
    setState(() => _error = null);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pas5'],
      );
      if (files.isEmpty) return;
      final bytes = await files.single.readAsBytes();

      final backup = PaperbackBackupParser.parse(bytes);
      if (backup.titles.isEmpty) {
        setState(() => _error = "That file didn't contain any recognizable library entries.");
        return;
      }
      setState(() {
        _backup = backup;
        _step = _Step.matching;
      });
      _runMatch(backup);
    } catch (e) {
      setState(() => _error = "Couldn't read that file: $e");
    }
  }

  void _runMatch(PaperbackBackup backup) {
    final backendAsync = ref.read(activeBackendProvider);
    final backend = backendAsync.valueOrNull;
    if (backend is! SuwayomiBackend) {
      setState(() {
        _error = 'Backup import needs your active server to be Suwayomi - '
            'that\'s the only backend with an equivalent to Paperback\'s scraper sources.';
        _step = _Step.pickFile;
      });
      return;
    }
    final controller = BackupImportController(backend: backend);
    controller.match(backup).listen((event) {
      if (!mounted) return;
      if (event is MatchProgress) {
        setState(() {
          _matchDone = event.done;
          _matchTotal = event.total;
          _matches.add(event.latest);
        });
      }
    }, onDone: () {
      if (mounted) setState(() => _step = _Step.review);
    });
  }

  void _runApply() {
    final backend = ref.read(activeBackendProvider).valueOrNull;
    if (backend is! SuwayomiBackend || _backup == null) return;
    setState(() => _step = _Step.applying);
    final controller = BackupImportController(backend: backend);
    controller.apply(_matches, _backup!).listen((event) {
      if (!mounted) return;
      if (event is ApplyProgress) {
        setState(() {
          _applyDone = event.done;
          _applyTotal = event.total;
          if (!event.ok) _applyErrors.add('${event.titleName}: ${event.error}');
        });
      }
    }, onDone: () {
      if (mounted) setState(() => _step = _Step.done);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: Row(
                children: [
                  _BackButton(onTap: () => context.pop()),
                  const SizedBox(width: 12),
                  Text('Import backup', style: AppText.largeTitle(size: 24)),
                ],
              ),
            ),
            Expanded(child: _buildStep()),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _Step.pickFile:
        return _PickFileStep(onPick: _pickFile, error: _error);
      case _Step.matching:
        return _MatchingStep(done: _matchDone, total: _matchTotal);
      case _Step.review:
        return _ReviewStep(
          matches: _matches,
          onToggleExclude: (m) => setState(() => m.excluded = !m.excluded),
          onApply: _runApply,
        );
      case _Step.applying:
        return _ApplyingStep(done: _applyDone, total: _applyTotal);
      case _Step.done:
        return _DoneStep(
          applied: _applyDone,
          total: _applyTotal,
          errors: _applyErrors,
          onFinish: () => context.pop(),
        );
    }
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.fillSubtle,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: AppColors.text),
        ),
      ),
    );
  }
}

class _PickFileStep extends StatelessWidget {
  final VoidCallback onPick;
  final String? error;
  const _PickFileStep({required this.onPick, this.error});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Paperback's export is a .pas5 file (Settings > Backups > Export "
            'in the Paperback app). This reads it locally in your browser - '
            'nothing is uploaded anywhere, and nothing is written to your '
            "server until you review and confirm the matches.",
            style: AppText.body(size: 13.5, color: AppColors.text60),
          ),
          const SizedBox(height: 20),
          InkWell(
            onTap: onPick,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderStrong, style: BorderStyle.solid),
              ),
              child: Row(
                children: [
                  Icon(Icons.upload_file_outlined, size: 22, color: AppColors.accentLink),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Choose .pas5 file', style: AppText.body(size: 14, weight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text('Nothing is written until you confirm',
                            style: AppText.body(size: 11, color: AppColors.text45)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.28)),
              ),
              child: Text(error!, style: AppText.body(size: 12.5, color: AppColors.dangerText)),
            ),
          ],
        ],
      ),
    );
  }
}

class _MatchingStep extends StatelessWidget {
  final int done;
  final int total;
  const _MatchingStep({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : done / total;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(value: progress == 0 ? null : progress),
            ),
            const SizedBox(height: 18),
            Text('Matching against your Suwayomi sources',
                style: AppText.body(size: 14, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('$done of $total titles', style: AppText.mono(size: 11)),
            const SizedBox(height: 8),
            Text('This can take a while - each title is a real search against an external site.',
                textAlign: TextAlign.center,
                style: AppText.body(size: 11.5, color: AppColors.text45)),
          ],
        ),
      ),
    );
  }
}

class _ReviewStep extends StatelessWidget {
  final List<TitleMatch> matches;
  final ValueChanged<TitleMatch> onToggleExclude;
  final VoidCallback onApply;
  const _ReviewStep({required this.matches, required this.onToggleExclude, required this.onApply});

  @override
  Widget build(BuildContext context) {
    final grouped = <MatchStatus, List<TitleMatch>>{};
    for (final m in matches) {
      (grouped[m.status] ??= []).add(m);
    }
    final applyCount =
        matches.where((m) => m.status == MatchStatus.highConfidence && !m.excluded).length;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            children: [
              for (final status in MatchStatus.values)
                if (grouped[status]?.isNotEmpty == true) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('${_statusLabel(status)} · ${grouped[status]!.length}',
                        style: AppText.sectionLabel()),
                  ),
                  for (final m in grouped[status]!) _MatchRow(match: m, onToggle: () => onToggleExclude(m)),
                ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: applyCount == 0 ? AppColors.fillSubtle : AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                  onPressed: applyCount == 0 ? null : onApply,
                  child: Text('Import $applyCount title${applyCount == 1 ? '' : 's'}',
                      style: AppText.body(
                          size: 15,
                          weight: FontWeight.w600,
                          color: applyCount == 0 ? AppColors.text45 : Colors.white)),
                ),
              ),
              const SizedBox(height: 8),
              Text('Only high-confidence matches are imported. Everything else needs a manual look.',
                  textAlign: TextAlign.center,
                  style: AppText.body(size: 10.5, color: AppColors.text42)),
            ],
          ),
        ),
      ],
    );
  }

  String _statusLabel(MatchStatus s) => switch (s) {
        MatchStatus.highConfidence => 'READY TO IMPORT',
        MatchStatus.review => 'NEEDS REVIEW',
        MatchStatus.lowConfidence => 'LOW CONFIDENCE',
        MatchStatus.noResults => 'NO RESULTS',
        MatchStatus.noMappableSource => 'NO SUWAYOMI SOURCE',
      };
}

class _MatchRow extends StatelessWidget {
  final TitleMatch match;
  final VoidCallback onToggle;
  const _MatchRow({required this.match, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final canToggle = match.status == MatchStatus.highConfidence;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(match.title.primaryTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(
                        size: 13.5,
                        color: match.excluded ? AppColors.text45 : AppColors.text,
                        weight: FontWeight.w500)),
                if (match.suwayomiMangaTitle != null) ...[
                  const SizedBox(height: 3),
                  Text('→ ${match.suwayomiMangaTitle}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.mono(size: 9.5)),
                ],
              ],
            ),
          ),
          if (canToggle)
            Switch(
              value: !match.excluded,
              onChanged: (_) => onToggle(),
              activeThumbColor: Colors.white,
              activeTrackColor: AppColors.accent,
            ),
        ],
      ),
    );
  }
}

class _ApplyingStep extends StatelessWidget {
  final int done;
  final int total;
  const _ApplyingStep({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : done / total;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 60, height: 60, child: CircularProgressIndicator(value: progress == 0 ? null : progress)),
            const SizedBox(height: 18),
            Text('Importing', style: AppText.body(size: 14, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('$done of $total', style: AppText.mono(size: 11)),
          ],
        ),
      ),
    );
  }
}

class _DoneStep extends StatelessWidget {
  final int applied;
  final int total;
  final List<String> errors;
  final VoidCallback onFinish;
  const _DoneStep({required this.applied, required this.total, required this.errors, required this.onFinish});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, size: 40, color: AppColors.suwayomiText),
          const SizedBox(height: 14),
          Text('Imported ${applied - errors.length} of $total titles',
              style: AppText.body(size: 16, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('Library, categories, and read progress are updated on your Suwayomi server.',
              style: AppText.body(size: 12.5, color: AppColors.text60)),
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('${errors.length} FAILED', style: AppText.sectionLabel(color: AppColors.dangerText)),
            const SizedBox(height: 8),
            Expanded(
              child: AppErrorState(error: errors.join('\n')),
            ),
          ] else
            const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
              ),
              onPressed: onFinish,
              child: Text('Done', style: AppText.body(size: 15, weight: FontWeight.w600, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
