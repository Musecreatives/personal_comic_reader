import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../core/history/history_entry.dart';

/// Wraps the 5 root tabs (Home, Search, Library, History, Settings) in a
/// persistent frosted-glass bottom nav bar. Only these 5 screens - the
/// `StatefulShellRoute` branch roots in `router.dart` - get this bar; any
/// sub-page reached from one of them (a series, the reader, a settings
/// detail screen) is a sibling route outside the shell and renders
/// full-screen without it, by design.
class GlassNavScaffold extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    // Latest unfinished read on this server, unless dismissed. Not shown on
    // Home (index 0): its hero already says the same thing, bigger.
    final latest = ref.watch(recentReadingProvider).firstOrNull;
    final dismissed = ref.watch(nowReadingDismissedProvider);
    final showBar = navigationShell.currentIndex != 0 &&
        latest != null &&
        !latest.completed &&
        latest.timestamp != dismissed;

    return Scaffold(
      backgroundColor: AppColors.page,
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showBar) _NowReadingBar(entry: latest),
            ClipRRect(
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
          ],
        ),
      ),
    );
  }
}

/// Floating "now reading" pill above the tab bar: the last unfinished
/// chapter and page, tap to resume exactly there, X to dismiss until the
/// next time something is read.
class _NowReadingBar extends ConsumerStatefulWidget {
  final HistoryEntry entry;
  const _NowReadingBar({required this.entry});

  @override
  ConsumerState<_NowReadingBar> createState() => _NowReadingBarState();
}

class _NowReadingBarState extends ConsumerState<_NowReadingBar> {
  String? _seriesId;
  Future<String?>? _title;

  // History stores the chapter title, not the series - look the series up
  // once per series rather than on every rebuild.
  Future<String?> _titleFor(String seriesId) async {
    final backend = ref.read(activeBackendProvider).valueOrNull;
    if (backend == null) return null;
    try {
      return (await backend.getSeries(seriesId)).title;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    if (_seriesId != e.seriesId) {
      _seriesId = e.seriesId;
      _title = _titleFor(e.seriesId);
    }
    final number = e.bookNumber.replaceFirst(RegExp(r'^0+(?=\d)'), '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Material(
            color: AppColors.card.withValues(alpha: 0.72),
            child: InkWell(
              onTap: () => context.push(
                  '/read/${Uri.encodeComponent(e.bookId)}?page=${e.lastPage}'),
              child: Container(
                height: 54,
                padding: const EdgeInsets.only(left: 16, right: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: FutureBuilder<String?>(
                        future: _title,
                        builder: (context, snap) => Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              snap.data ?? e.bookTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body(size: 13.5, weight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Ch. $number · page ${e.lastPage + 1} of ${e.pageCount}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.mono(size: 9.5, color: AppColors.text60),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Dismiss',
                      icon: Icon(Icons.close, size: 18, color: AppColors.text60),
                      onPressed: () =>
                          ref.read(nowReadingDismissedProvider.notifier).state = e.timestamp,
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
