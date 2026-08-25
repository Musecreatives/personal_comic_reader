import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';

enum DockTab { reading, library, sources, downloads, you }

/// The persistent bottom "dock" from the 3a design: a floating glass pill
/// with 5 destinations. [onLibraryTap] is passed in because "Library" needs
/// to resolve which library id to push (the backend has no single
/// aggregate library route).
class ReadingNowDock extends StatelessWidget {
  final DockTab active;
  final VoidCallback? onLibraryTap;

  const ReadingNowDock({super.key, required this.active, this.onLibraryTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 26),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 62,
            decoration: BoxDecoration(
              color: AppColors.canvas.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.borderStrong),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _DockItem(
                  icon: Icons.menu_book_outlined,
                  label: 'Reading',
                  isActive: active == DockTab.reading,
                  onTap: () => context.go('/home'),
                ),
                _DockItem(
                  icon: Icons.grid_view_rounded,
                  label: 'Library',
                  isActive: active == DockTab.library,
                  onTap: onLibraryTap ?? () {},
                ),
                _DockItem(
                  icon: Icons.dns_outlined,
                  label: 'Sources',
                  isActive: active == DockTab.sources,
                  onTap: () => context.push('/settings/servers'),
                ),
                _DockItem(
                  icon: Icons.download_outlined,
                  label: 'Downloads',
                  isActive: active == DockTab.downloads,
                  onTap: () => context.push('/settings/downloads'),
                ),
                _DockItem(
                  icon: Icons.person_outline,
                  label: 'You',
                  isActive: active == DockTab.you,
                  onTap: () => context.push('/settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _DockItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.accentLink : AppColors.text45;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 5),
            Text(
              label,
              style: AppText.body(
                size: 9.5,
                weight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
