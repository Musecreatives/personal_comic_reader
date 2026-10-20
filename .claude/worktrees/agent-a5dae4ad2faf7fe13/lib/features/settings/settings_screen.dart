import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../app/providers.dart';
import '../shared/back_button.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 24),
          children: [
            const AppScreenHeader(title: 'Settings', titleSize: 30),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.accent.withValues(alpha: 0.16),
                      AppColors.card,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Image.asset('assets/icon/app_icon.png', fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Text('Shaddai Reader',
                          style: AppText.body(size: 14.5, weight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
            _SectionLabel('SYNC'),
            _SettingsGroup(children: [const _SyncRow()]),
            _SectionLabel('LIBRARY'),
            _SettingsGroup(children: [
              _SettingsRow(
                icon: Icons.dns_outlined,
                title: 'Sources & servers',
                subtitle: 'Add, edit, or switch between servers',
                onTap: () => context.push('/settings/servers'),
              ),
              _SettingsRow(
                icon: Icons.download_outlined,
                title: 'Kapowarr',
                subtitle: 'Acquisition status - not a reading source',
                onTap: () => context.push('/settings/kapowarr'),
              ),
              _SettingsRow(
                icon: Icons.health_and_safety_outlined,
                title: 'Suwayomi maintenance',
                subtitle: 'Extension health, backup & restore',
                onTap: () => context.push('/settings/suwayomi'),
              ),
              _SettingsRow(
                icon: Icons.downloading_outlined,
                title: 'Downloads',
                subtitle: 'Queue, pause/resume, Wi-Fi-only',
                onTap: () => context.push('/settings/downloads'),
                isLast: false,
              ),
              _SettingsRow(
                icon: Icons.storage_outlined,
                title: 'Storage',
                subtitle: 'Downloaded size per series, clear cache',
                onTap: () => context.push('/settings/storage'),
              ),
              _SettingsRow(
                icon: Icons.folder_zip_outlined,
                title: 'On This Device',
                subtitle: 'Import and read CBZ/ZIP files directly',
                onTap: () => context.push('/local-library'),
              ),
              _SettingsRow(
                icon: Icons.cloud_upload_outlined,
                title: 'Media Pool',
                subtitle: 'Back up locally-imported comics over WebDAV',
                onTap: () => context.push('/settings/media-pool'),
              ),
              _SettingsRow(
                icon: Icons.travel_explore_outlined,
                title: 'ComicVine',
                subtitle: 'API key for looking up imported comics',
                onTap: () => context.push('/settings/comicvine'),
                isLast: true,
              ),
            ]),
            _SectionLabel('YOU'),
            _SettingsGroup(children: [
              _SettingsRow(
                icon: Icons.palette_outlined,
                title: 'Appearance',
                subtitle: 'Theme and accent color',
                onTap: () => context.push('/settings/appearance'),
              ),
              _SettingsRow(
                icon: Icons.bar_chart_outlined,
                title: 'Reading stats',
                subtitle: 'Streak and pages per day, across your devices',
                onTap: () => context.push('/stats'),
              ),
              _SettingsRow(
                icon: Icons.history,
                title: 'History',
                subtitle: 'Recently read, across your devices',
                onTap: () => context.push('/history'),
              ),
              _SettingsRow(
                icon: Icons.collections_bookmark_outlined,
                title: 'Collections',
                subtitle: 'Local shelves that cross servers',
                onTap: () => context.push('/collections'),
                isLast: true,
              ),
            ]),
            _SectionLabel('HELP'),
            _SettingsGroup(children: [
              _SettingsRow(
                icon: Icons.bug_report_outlined,
                title: 'Diagnostics & reports',
                subtitle: 'Network and logs, report a problem, debug mode',
                onTap: () => context.push('/debug'),
                isLast: true,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Sync state at a glance: who is signed in, whether a sync is running or
/// failed, and when the last good one finished. Tapping syncs now. The icon
/// spins only while a sync is actually in flight.
class _SyncRow extends ConsumerStatefulWidget {
  const _SyncRow();

  @override
  ConsumerState<_SyncRow> createState() => _SyncRowState();
}

class _SyncRowState extends ConsumerState<_SyncRow>
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
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
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

    final last = status.lastOk;
    final subtitle = switch (status.phase) {
      SyncPhase.syncing => 'Syncing…',
      SyncPhase.offline =>
        "Can't reach the sync server. Your changes are kept and sent later.",
      SyncPhase.idle => last == null
          ? 'Tap to sync history, collections and settings'
          : 'Up to date · synced ${_ago(last)}',
    };

    return InkWell(
      onTap: user == null || syncing
          ? null
          : () => startSync(ProviderScope.containerOf(context)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            RotationTransition(
              turns: _spin,
              child: Icon(
                status.phase == SyncPhase.offline
                    ? Icons.sync_problem_outlined
                    : Icons.sync,
                size: 20,
                color: status.phase == SyncPhase.offline
                    ? Colors.orangeAccent
                    : AppColors.text60,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user == null ? 'Not signed in' : 'Signed in as $user',
                    style: AppText.body(size: 14, weight: FontWeight.w500),
                  ),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: AppText.body(size: 11, color: AppColors.text45)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
      child: Text(label, style: AppText.sectionLabel()),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isLast;

  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.text60),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.body(size: 14, weight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: AppText.body(size: 11, color: AppColors.text45)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.text30),
          ],
        ),
      ),
    );
  }
}
