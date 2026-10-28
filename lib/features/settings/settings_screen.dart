import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/brand_seal.dart';
import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../core/appearance/appearance_settings.dart';
import '../../core/downloads/download_models.dart';

/// Current reading streak in days, for the Reading stats row.
final readingStreakProvider = Provider<int>((ref) {
  ref.watch(statsRevisionProvider);
  return ref.watch(readingStatsStoreProvider).currentStreak;
});

/// How many collections exist, for the Collections row.
final collectionCountProvider = Provider<int>((ref) {
  ref.watch(collectionsRevisionProvider);
  return ref.watch(collectionsStoreProvider).list().length;
});

/// Settings as in the prototype: an account block with sync status, then
/// hairline panels per group. Server tools are one "Server admin" group that
/// only the owner sees, instead of being scattered through Library.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(isOwnerProvider);
    final mode = ref.watch(appearanceProvider).themeMode;
    // Live status beside a row, where it is cheap to know. Storage size (a
    // disk walk) and pending requests (a network call) stay on their pages.
    final queued = (ref.watch(downloadQueueProvider).valueOrNull ?? const [])
        .where(
          (t) =>
              t.state == DownloadState.queued ||
              t.state == DownloadState.running,
        )
        .length;
    final streak = ref.watch(readingStreakProvider);
    final shelves = ref.watch(collectionCountProvider);
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              // Room at the foot for the now-reading pill.
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 112),
              children: [
                Text('Settings', style: AppText.largeTitle()),
                const SizedBox(height: 18),
                const _AccountBlock(),
                const _GroupLabel('LIBRARY'),
                _Group(
                  rows: [
                    _Row(
                      'Sources & servers',
                      'Komga, Suwayomi and OPDS',
                      () => context.push('/settings/servers'),
                    ),
                    _Row(
                      owner ? 'Sources & extensions' : 'Sources',
                      'Where Suwayomi finds manga and comics',
                      () => context.push('/settings/sources'),
                    ),
                    _Row(
                      'Downloads',
                      'Queue, pause and resume, Wi-Fi only',
                      () => context.push('/settings/downloads'),
                      meta: queued > 0 ? '$queued QUEUED' : null,
                    ),
                    _Row(
                      'Storage',
                      'Space used per series, clear the cache',
                      () => context.push('/settings/storage'),
                    ),
                    _Row(
                      'On This Device',
                      'Import and read CBZ and ZIP files',
                      () => context.push('/local-library'),
                    ),
                    _Row(
                      'ComicVine',
                      'API key for looking up imported comics',
                      () => context.push('/settings/comicvine'),
                    ),
                    if (!owner)
                      _Row(
                        'My requests',
                        'Series you asked for, and where they stand',
                        () => context.push('/settings/requests'),
                      ),
                  ],
                ),
                const _GroupLabel('YOU'),
                _Group(
                  rows: [
                    _Row(
                      'Appearance',
                      null,
                      () => context.push('/settings/appearance'),
                      meta: _modeName(mode),
                    ),
                    _Row(
                      'Reading stats',
                      'Streak and pages per day',
                      () => context.push('/stats'),
                      meta: streak > 0 ? '$streak-DAY STREAK' : null,
                    ),
                    _Row(
                      'History',
                      'Recently read, across your devices',
                      () => context.push('/history'),
                    ),
                    _Row(
                      'Collections',
                      'Shelves that cross servers',
                      () => context.push('/collections'),
                      meta: shelves > 0 ? '$shelves' : null,
                    ),
                  ],
                ),
                if (owner) ...[
                  const _GroupLabel('SERVER ADMIN'),
                  _Group(
                    rows: [
                      _Row(
                        'Requests',
                        'Series your friends asked for',
                        () => context.push('/settings/requests'),
                      ),
                      _Row(
                        'Invite friends',
                        'One code per friend, revoke unused ones',
                        () => context.push('/settings/invites'),
                      ),
                      _Row(
                        'Kapowarr',
                        'Acquisition status',
                        () => context.push('/settings/kapowarr'),
                      ),
                      _Row(
                        'Suwayomi maintenance',
                        'Extension health, backup and restore',
                        () => context.push('/settings/suwayomi'),
                      ),
                      _Row(
                        'Media Pool',
                        'Back up imported comics over WebDAV',
                        () => context.push('/settings/media-pool'),
                      ),
                    ],
                  ),
                ],
                const _GroupLabel('HELP'),
                _Group(
                  rows: [
                    _Row(
                      'Diagnostics & reports',
                      'Network and logs, report a problem',
                      () => context.push('/debug'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _modeName(AppThemeMode m) => switch (m) {
    AppThemeMode.midnight => 'MIDNIGHT',
    AppThemeMode.paper => 'WASHI',
    AppThemeMode.trueBlack => 'OLED',
    AppThemeMode.system => 'SYSTEM',
  };
}

/// Who is signed in and how sync stands, on screentone in a 2px ink frame
/// with the seal. Tapping syncs now; the icon spins only while a sync runs.
class _AccountBlock extends ConsumerStatefulWidget {
  const _AccountBlock();

  @override
  ConsumerState<_AccountBlock> createState() => _AccountBlockState();
}

class _AccountBlockState extends ConsumerState<_AccountBlock>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'JUST NOW';
    if (d.inMinutes < 60) return '${d.inMinutes} MIN AGO';
    if (d.inHours < 24) return '${d.inHours} H AGO';
    return '${d.inDays} D AGO';
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(syncStatusProvider);
    final user = ref.watch(currentUsernameProvider);
    final syncing = status.phase == SyncPhase.syncing;
    if (syncing && !_spin.isAnimating && !Motion.reduced(context)) {
      _spin.repeat();
    } else if (!syncing && _spin.isAnimating) {
      _spin.stop();
    }
    final offline = status.phase == SyncPhase.offline;
    // The server is changed by signing out: a session only works on the
    // server that issued it.
    final host = user == null
        ? ''
        : Uri.tryParse(ref.read(syncClientProvider).baseUrl)?.host ?? '';
    final last = status.lastOk;
    final line = switch (status.phase) {
      SyncPhase.syncing => 'SYNCING',
      SyncPhase.offline => "CAN'T REACH THE SYNC SERVER · CHANGES ARE KEPT",
      SyncPhase.idle => last == null ? 'TAP TO SYNC' : 'SYNCED ${_ago(last)}',
    };

    return Semantics(
      button: user != null && !syncing,
      label: 'Sync now',
      // Pressing in, like every tappable surface (DESIGN.md motion).
      child: PressScale(
        child: GestureDetector(
          onTap: user == null || syncing
              ? null
              : () => startSync(ProviderScope.containerOf(context)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border.all(color: AppColors.text, width: 2),
            ),
            child: CustomPaint(
              painter: Screentone(AppColors.text.withValues(alpha: 0.12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const BrandSeal(size: 44),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user ?? 'Not signed in',
                            style: AppText.body(
                              size: 16,
                              weight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            host.isEmpty
                                ? line
                                : '$line · ${host.toUpperCase()}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.mono(
                              size: 10.5,
                              color: offline
                                  ? AppColors.warningText
                                  : AppColors.text60,
                            ),
                          ),
                        ],
                      ),
                    ),
                    RotationTransition(
                      turns: _spin,
                      child: Icon(
                        offline ? Icons.sync_problem_outlined : Icons.sync,
                        size: 20,
                        color: offline
                            ? AppColors.warningText
                            : AppColors.text60,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String label;
  const _GroupLabel(this.label);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 24, 0, 8),
    child: Text(label, style: AppText.sectionLabel()),
  );
}

class _Row {
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final String? meta;
  const _Row(this.title, this.subtitle, this.onTap, {this.meta});
}

/// One hairline panel of rows, separated by hairlines (no card per row).
class _Group extends StatelessWidget {
  final List<_Row> rows;
  const _Group({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: rows[i].onTap,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rows[i].title,
                              style: AppText.body(
                                size: 15,
                                weight: FontWeight.w500,
                              ),
                            ),
                            if (rows[i].subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                rows[i].subtitle!,
                                style: AppText.body(
                                  size: 12.5,
                                  color: AppColors.text60,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (rows[i].meta != null) ...[
                        Text(
                          rows[i].meta!,
                          style: AppText.mono(
                            size: 11,
                            color: AppColors.text60,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppColors.text60,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
