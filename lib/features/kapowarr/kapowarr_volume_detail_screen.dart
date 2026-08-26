import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../core/kapowarr/kapowarr_client.dart';
import '../shared/error_state.dart';

/// A single Kapowarr volume (5d): hero, progress, and a real per-issue
/// status list. Read-only, like the rest of the Kapowarr integration - no
/// monitor/search actions live here.
class KapowarrVolumeDetailScreen extends ConsumerStatefulWidget {
  final int volumeId;
  const KapowarrVolumeDetailScreen({super.key, required this.volumeId});

  @override
  ConsumerState<KapowarrVolumeDetailScreen> createState() => _KapowarrVolumeDetailScreenState();
}

class _KapowarrVolumeDetailScreenState extends ConsumerState<KapowarrVolumeDetailScreen> {
  late Future<KapowarrVolume> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<KapowarrVolume> _load() async {
    final config = await ref.read(kapowarrConfigStoreProvider).getWithApiKey();
    if (config == null) throw StateError('Kapowarr is not configured');
    return KapowarrClient(config: config).getVolume(widget.volumeId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: FutureBuilder<KapowarrVolume>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return AppErrorState(
                  error: snapshot.error!, onRetry: () => setState(() => _future = _load()));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final v = snapshot.data!;
            final progress = v.issueCount == 0 ? 0.0 : v.issuesDownloaded / v.issueCount;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
              children: [
                Row(
                  children: [
                    _BackButton(onTap: () => context.pop()),
                    const SizedBox(width: 12),
                    Text('KAPOWARR · VOLUME', style: AppText.mono(size: 9, color: AppColors.text45)),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.kapowarr.withValues(alpha: 0.14), AppColors.card],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.kapowarr.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v.title, style: AppText.largeTitle(size: 20)),
                      const SizedBox(height: 6),
                      Text('${v.publisher} · ${v.year}',
                          style: AppText.body(size: 12, color: AppColors.text60)),
                      const SizedBox(height: 11),
                      Wrap(
                        spacing: 6,
                        children: [
                          if (v.monitored)
                            _Pill(label: 'MONITORED', color: AppColors.kavitaText, bg: AppColors.kavita.withValues(alpha: 0.2))
                          else
                            _Pill(label: 'UNMONITORED', color: AppColors.text45, bg: AppColors.fillSubtle),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 4,
                                backgroundColor: AppColors.track,
                                valueColor: AlwaysStoppedAnimation(AppColors.kapowarr),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text('${v.issuesDownloaded}/${v.issueCount}', style: AppText.mono(size: 10)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text('ISSUES', style: AppText.sectionLabel()),
                const SizedBox(height: 8),
                for (final issue in v.issues) _IssueRow(issue: issue),
              ],
            );
          },
        ),
      ),
    );
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

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const _Pill({required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: AppText.mono(size: 9, color: color)),
    );
  }
}

class _IssueRow extends StatelessWidget {
  final KapowarrIssue issue;
  const _IssueRow({required this.issue});

  @override
  Widget build(BuildContext context) {
    final Color stateColor;
    final String stateLabel;
    if (issue.hasFile) {
      stateColor = AppColors.suwayomiText;
      stateLabel = 'DOWNLOADED';
    } else if (issue.monitored) {
      stateColor = AppColors.kavitaText;
      stateLabel = 'WANTED';
    } else {
      stateColor = AppColors.text30;
      stateLabel = 'NOT MONITORED';
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text('#${issue.issueNumber}', style: AppText.mono(size: 10, color: AppColors.text45)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(issue.title?.isNotEmpty == true ? issue.title! : 'Untitled',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(size: 14)),
                if (issue.date != null) ...[
                  const SizedBox(height: 3),
                  Text(issue.date!, style: AppText.mono(size: 9, color: AppColors.text45)),
                ],
              ],
            ),
          ),
          Text(stateLabel, style: AppText.mono(size: 9, color: stateColor)),
        ],
      ),
    );
  }
}
