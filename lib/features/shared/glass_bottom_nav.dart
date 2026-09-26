import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../core/history/history_entry.dart';

/// Below this width the 5 root tabs sit in a floating glass bar at the
/// bottom (phone); at or above it they move to a side rail (tablet/desktop).
const _railBreakpoint = 900.0;

/// Widest the page content grows on big screens - past this, lists and
/// forms stretch into unreadable lines.
const _maxContentWidth = 1200.0;

/// Wraps the 5 root tabs (Home, Search, Library, History, Settings) in a
/// persistent nav: a frosted-glass floating bar on phones, a side rail on
/// wide screens. Only these 5 screens - the `StatefulShellRoute` branch
/// roots in `router.dart` - get it; any sub-page reached from one of them
/// (a series, the reader, a settings detail screen) is a sibling route
/// outside the shell and renders full-screen without it, by design.
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

  void _select(int i) => navigationShell.goBranch(
        i,
        initialLocation: i == navigationShell.currentIndex,
      );

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
    final pill = _NowReadingSlot(entry: showBar ? latest : null);
    final index = navigationShell.currentIndex;

    if (MediaQuery.sizeOf(context).width >= _railBreakpoint) {
      return Scaffold(
        backgroundColor: AppColors.page,
        body: Row(
          children: [
            _SideRail(tabs: _tabs, index: index, onSelect: _select),
            Expanded(
              child: Stack(
                children: [
                  _TabFade(
                    index: index,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: _maxContentWidth),
                        child: navigationShell,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: pill,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.page,
      extendBody: true,
      body: _TabFade(index: index, child: navigationShell),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                pill,
                _BottomBar(tabs: _tabs, index: index, onSelect: _select),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

typedef _Tab = ({IconData icon, String label});

/// Softly fades the page in when the tab changes. The child is the same
/// widget instance throughout, so no branch state is remounted.
class _TabFade extends StatefulWidget {
  final int index;
  final Widget child;
  const _TabFade({required this.index, required this.child});

  @override
  State<_TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<_TabFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Motion.fast, value: 1);

  @override
  void didUpdateWidget(_TabFade old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && !Motion.reduced(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _c, curve: Motion.easeOut)
          .drive(Tween(begin: 0.55, end: 1)),
      child: widget.child,
    );
  }
}

/// The floating glass tab bar. A capsule slides behind whichever tab is
/// selected instead of the colour just snapping.
class _BottomBar extends StatelessWidget {
  final List<_Tab> tabs;
  final int index;
  final ValueChanged<int> onSelect;
  const _BottomBar(
      {required this.tabs, required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
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
          child: LayoutBuilder(builder: (context, c) {
            final itemW = c.maxWidth / tabs.length;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: Motion.scaled(context, Motion.base),
                  curve: Motion.easeOut,
                  left: itemW * index + 4,
                  top: 6,
                  width: itemW - 8,
                  height: 52,
                  child: const _Capsule(),
                ),
                Row(
                  children: [
                    for (var i = 0; i < tabs.length; i++)
                      Expanded(
                        child: _NavItem(
                          icon: tabs[i].icon,
                          label: tabs[i].label,
                          selected: index == i,
                          onTap: () => onSelect(i),
                        ),
                      ),
                  ],
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

/// The wide-screen counterpart: a vertical rail with the same sliding
/// capsule.
class _SideRail extends StatelessWidget {
  final List<_Tab> tabs;
  final int index;
  final ValueChanged<int> onSelect;
  const _SideRail(
      {required this.tabs, required this.index, required this.onSelect});

  static const _itemH = 60.0;
  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      decoration: BoxDecoration(
        color: AppColors.canvas,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
          child: Column(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text('SR',
                    style: AppText.mono(
                        size: 12,
                        weight: FontWeight.w700,
                        color: AppColors.accentSoft)),
              ),
              const SizedBox(height: 26),
              SizedBox(
                height: tabs.length * _itemH + (tabs.length - 1) * _gap,
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: Motion.scaled(context, Motion.base),
                      curve: Motion.easeOut,
                      top: index * (_itemH + _gap),
                      left: 0,
                      right: 0,
                      height: _itemH,
                      child: const _Capsule(),
                    ),
                    Column(
                      children: [
                        for (var i = 0; i < tabs.length; i++) ...[
                          if (i > 0) const SizedBox(height: _gap),
                          SizedBox(
                            height: _itemH,
                            child: _NavItem(
                              icon: tabs[i].icon,
                              label: tabs[i].label,
                              selected: index == i,
                              onTap: () => onSelect(i),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Capsule extends StatelessWidget {
  const _Capsule();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
        ),
      );
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
    final color = selected ? AppColors.accentLink : AppColors.text45;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: PressScale(
          child: InkWell(
            onTap: onTap,
            customBorder:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: color),
              duration: Motion.scaled(context, Motion.fast),
              curve: Motion.easeOut,
              builder: (context, c, _) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedScale(
                    scale: selected ? 1.08 : 1,
                    duration: Motion.scaled(context, Motion.base),
                    curve: Motion.easeOut,
                    child: Icon(icon, size: 22, color: c),
                  ),
                  const SizedBox(height: 3),
                  Text(label,
                      style: AppText.body(
                          size: 10.5, weight: FontWeight.w600, color: c)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Holds the now-reading pill's place so it can slide in and out (and grow
/// or collapse the space it takes) instead of popping.
class _NowReadingSlot extends StatelessWidget {
  final HistoryEntry? entry;
  const _NowReadingSlot({required this.entry});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: Motion.scaled(context, Motion.base),
      curve: Motion.easeOut,
      alignment: Alignment.bottomCenter,
      child: AnimatedSwitcher(
        duration: Motion.scaled(context, Motion.base),
        reverseDuration: Motion.scaled(context, Motion.fast),
        switchInCurve: Motion.easeOut,
        switchOutCurve: Motion.easeOut,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.3), end: Offset.zero)
                .animate(anim),
            child: child,
          ),
        ),
        child: entry == null
            ? const SizedBox(key: ValueKey('none'), width: double.infinity)
            : _NowReadingBar(key: ValueKey(entry!.bookId), entry: entry!),
      ),
    );
  }
}

/// Floating "now reading" pill above the tab bar: the last unfinished
/// chapter and page, tap to resume exactly there, X to dismiss until the
/// next time something is read.
class _NowReadingBar extends ConsumerStatefulWidget {
  final HistoryEntry entry;
  const _NowReadingBar({super.key, required this.entry});

  @override
  ConsumerState<_NowReadingBar> createState() => _NowReadingBarState();
}

class _NowReadingBarState extends ConsumerState<_NowReadingBar> {
  String? _seriesId;
  Future<String?>? _title;

  // History stores the chapter title, not the series - look the series up
  // once per series rather than on every rebuild.
  Future<String?> _titleFor(String? serverId, String seriesId) async {
    try {
      final backend = await ref.read(backendForServerProvider(serverId).future);
      if (backend == null) return null;
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
      _title = _titleFor(e.serverId, e.seriesId);
    }
    final number = e.bookNumber.replaceFirst(RegExp(r'^0+(?=\d)'), '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PressScale(
        scale: 0.985,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Material(
              color: AppColors.card.withValues(alpha: 0.72),
              child: InkWell(
                onTap: () async {
                  // The entry may be from another server than the active one.
                  await activateServer(ref, e.serverId);
                  if (!context.mounted) return;
                  context.push(
                      '/read/${Uri.encodeComponent(e.bookId)}?page=${e.lastPage}');
                },
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.border.withValues(alpha: 0.6)),
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
                                style: AppText.body(
                                    size: 13.5, weight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Ch. $number · page ${e.lastPage + 1} of ${e.pageCount}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.mono(
                                    size: 9.5, color: AppColors.text60),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Dismiss',
                        icon: Icon(Icons.close,
                            size: 18, color: AppColors.text60),
                        onPressed: () => ref
                            .read(nowReadingDismissedProvider.notifier)
                            .state = e.timestamp,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
