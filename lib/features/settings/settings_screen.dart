import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';

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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
              child: Text('Settings', style: AppText.largeTitle()),
            ),
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
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text('SR', style: AppText.mono(size: 13, weight: FontWeight.w700, color: AppColors.accentSoft)),
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
                isLast: true,
              ),
            ]),
            _SectionLabel('YOU'),
            _SettingsGroup(children: [
              _SettingsRow(
                icon: Icons.bar_chart_outlined,
                title: 'Reading stats',
                subtitle: 'Streak, pages per day - local only',
                onTap: () => context.push('/stats'),
                isLast: true,
              ),
            ]),
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
