import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';

/// Wraps the 5 root tabs (Home, Search, Library, History, Settings) in a
/// persistent frosted-glass bottom nav bar. Only these 5 screens - the
/// `StatefulShellRoute` branch roots in `router.dart` - get this bar; any
/// sub-page reached from one of them (a series, the reader, a settings
/// detail screen) is a sibling route outside the shell and renders
/// full-screen without it, by design.
class GlassNavScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const GlassNavScaffold({super.key, required this.navigationShell});

  static const _tabs = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.search_rounded, label: 'Search'),
    (icon: Icons.auto_stories_rounded, label: 'Library'),
    (icon: Icons.history_rounded, label: 'History'),
    (icon: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.card.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    Expanded(
                      child: _NavItem(
                        icon: _tabs[i].icon,
                        label: _tabs[i].label,
                        selected: navigationShell.currentIndex == i,
                        onTap: () => navigationShell.goBranch(
                          i,
                          initialLocation: i == navigationShell.currentIndex,
                        ),
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

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.text45;
    return InkWell(
      onTap: onTap,
      customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 3),
          Text(label, style: AppText.mono(size: 9, color: color)),
        ],
      ),
    );
  }
}
