import 'dart:ui';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../home/home_feed.dart';
import '../../app/motion.dart';
import '../../app/platform_style.dart';
import '../../app/providers.dart';
import '../../core/history/history_entry.dart';
import '../../app/brand_seal.dart';
import 'series_cover.dart';

/// Below this width the iOS tabs sit in a floating glass bar at the
/// bottom (iPhone); at or above it they move to a sidebar (iPad).
const _iosSidebarBreakpoint = 900.0;

/// Widest the page content grows on big screens - past this, lists and
/// forms stretch into unreadable lines.
const _maxContentWidth = 1200.0;

/// Wraps the 5 root tabs (Home, Search, Library, History, Settings) in a
/// persistent nav that follows the platform's own convention:
///
/// * iOS: a floating frosted tab bar (iPhone), a sidebar (iPad).
/// * Android: a Material 3 navigation bar, then from 600dp today's compact
///   rail with the seal, at every tablet width (canvas "Android tablet").
/// * Windows: a Fluent navigation pane, compact icons below 1280px and
///   expanded with labels above, Settings pinned to the foot like every
///   Windows app.
/// * Web: a navigation bar on phones, a rail on tablets, a labelled
///   sidebar on desktop.
///
/// Only these 5 screens - the `StatefulShellRoute` branch roots in
/// `router.dart` - get it; any sub-page reached from one of them (a
/// series, the reader, a settings detail screen) is a sibling route
/// outside the shell and renders full-screen without it, by design.
class GlassNavScaffold extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const GlassNavScaffold({super.key, required this.navigationShell});

  static List<_Tab> get _tabs => switch (PlatformStyle.current) {
    UiPlatform.ios => const [
      (
        icon: CupertinoIcons.house,
        selectedIcon: CupertinoIcons.house_fill,
        label: 'Home',
      ),
      (
        icon: CupertinoIcons.search,
        selectedIcon: CupertinoIcons.search,
        label: 'Search',
      ),
      (
        icon: CupertinoIcons.book,
        selectedIcon: CupertinoIcons.book_fill,
        label: 'Library',
      ),
      (
        icon: CupertinoIcons.clock,
        selectedIcon: CupertinoIcons.clock_fill,
        label: 'History',
      ),
      (
        icon: CupertinoIcons.gear_alt,
        selectedIcon: CupertinoIcons.gear_alt_fill,
        label: 'Settings',
      ),
    ],
    // Material and Fluent both draw outlined icons at rest and filled
    // ones when selected.
    _ => const [
      (
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
        label: 'Home',
      ),
      (
        icon: Icons.search_rounded,
        selectedIcon: Icons.search_rounded,
        label: 'Search',
      ),
      (
        icon: Icons.auto_stories_outlined,
        selectedIcon: Icons.auto_stories_rounded,
        label: 'Library',
      ),
      (
        icon: Icons.history_rounded,
        selectedIcon: Icons.history_rounded,
        label: 'History',
      ),
      (
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
        label: 'Settings',
      ),
    ],
  };

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
    // Hidden while typing too: with the keyboard up it would sit on the
    // results.
    final showBar =
        navigationShell.currentIndex != 0 &&
        MediaQuery.viewInsetsOf(context).bottom == 0 &&
        latest != null &&
        !latest.completed &&
        latest.timestamp != dismissed;
    final pill = _NowReadingSlot(entry: showBar ? latest : null);
    final index = navigationShell.currentIndex;
    final tabs = _tabs;
    final width = MediaQuery.sizeOf(context).width;

    final Widget scaffold = switch (PlatformStyle.current) {
      UiPlatform.ios =>
        width >= _iosSidebarBreakpoint
            ? _wide(
                _SideRail(tabs: tabs, index: index, onSelect: _select),
                pill,
              )
            : _iosPhone(tabs, index, pill),
      UiPlatform.android || UiPlatform.web =>
        width < Breakpoints.compact
            ? _materialPhone(context, tabs, index, pill)
            : PlatformStyle.isWeb && width >= Breakpoints.sidebar
            ? _wide(
                _Sidebar(
                  tabs: tabs,
                  index: index,
                  onSelect: _select,
                  expanded: true,
                ),
                pill,
              )
            : _wide(
                _MaterialRail(tabs: tabs, index: index, onSelect: _select),
                pill,
              ),
      UiPlatform.windows => _wide(
        _Sidebar(
          tabs: tabs,
          index: index,
          onSelect: _select,
          expanded: width >= Breakpoints.sidebar,
        ),
        pill,
      ),
    };

    if (!PlatformStyle.isDesktopLike) return scaffold;
    // Keyboard-first platforms: Ctrl+1-5 jumps between tabs, Ctrl+F (or
    // Ctrl+K, the web convention) opens Search.
    return CallbackShortcuts(
      bindings: {
        for (var i = 0; i < tabs.length; i++)
          SingleActivator(
            LogicalKeyboardKey(0x00000000031 + i),
            control: true,
          ): () =>
              _select(i),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _select(1),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _select(1),
      },
      child: Focus(autofocus: true, child: scaffold),
    );
  }

  /// Nav on the left, content capped at [_maxContentWidth], the
  /// now-reading pill floating over the foot of the content.
  Widget _wide(Widget nav, Widget pill) => Scaffold(
    backgroundColor: AppColors.page,
    body: Row(
      children: [
        nav,
        Expanded(
          child: Stack(
            children: [
              _TabFade(
                index: navigationShell.currentIndex,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _maxContentWidth,
                    ),
                    child: navigationShell,
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                // Edge-to-edge: keep the pill above the system nav bar.
                child: SafeArea(
                  top: false,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: pill,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _iosPhone(List<_Tab> tabs, int index, Widget pill) => Scaffold(
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
              _BottomBar(tabs: tabs, index: index, onSelect: _select),
            ],
          ),
        ),
      ),
    ),
  );

  /// Material 3 navigation bar, edge to edge, with the now-reading pill
  /// docked above it like a mini player.
  Widget _materialPhone(
    BuildContext context,
    List<_Tab> tabs,
    int index,
    Widget pill,
  ) => Scaffold(
    backgroundColor: AppColors.page,
    body: _TabFade(index: index, child: navigationShell),
    bottomNavigationBar: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: pill,
        ),
        DecoratedBox(
          // DESIGN.md: a 2px control line along the tab bar's top edge.
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.text, width: 2)),
          ),
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: _select,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              for (final t in tabs)
                NavigationDestination(
                  icon: Icon(t.icon),
                  selectedIcon: Icon(t.selectedIcon),
                  label: t.label,
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

typedef _Tab = ({IconData icon, IconData selectedIcon, String label});

/// Material 3 navigation rail (tablets, small desktop windows): icons with
/// labels underneath, never extended.
class _MaterialRail extends StatelessWidget {
  final List<_Tab> tabs;
  final int index;
  final ValueChanged<int> onSelect;
  const _MaterialRail({
    required this.tabs,
    required this.index,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: _FitOrScroll(child: _rail()),
    );
  }

  Widget _rail() => NavigationRail(
    selectedIndex: index,
    onDestinationSelected: onSelect,
    labelType: NavigationRailLabelType.all,
    groupAlignment: -0.85,
    leading: const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: BrandSeal(size: 48),
    ),
    destinations: [
      for (final t in tabs)
        NavigationRailDestination(
          icon: Icon(t.icon),
          selectedIcon: Icon(t.selectedIcon),
          label: Text(t.label),
        ),
    ],
  );
}

/// Side navs are fixed columns. Laid out at full height when they fit, they
/// scroll when they don't: the keyboard takes ~400px of a landscape tablet,
/// and the rail overflowed by 112px under it.
class _FitOrScroll extends StatelessWidget {
  final Widget child;
  const _FitOrScroll({required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: box.maxHeight),
        child: IntrinsicHeight(child: child),
      ),
    ),
  );
}

/// A Fluent-style navigation pane (Windows) and the desktop web sidebar:
/// a column of rows with a hover fill and a short accent bar marking the
/// selected one, the last tab (Settings) pinned to the foot. Collapsed it
/// shows icons only, with the label as a tooltip.
class _Sidebar extends StatelessWidget {
  final List<_Tab> tabs;
  final int index;
  final ValueChanged<int> onSelect;
  final bool expanded;
  const _Sidebar({
    required this.tabs,
    required this.index,
    required this.onSelect,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    final fluent = PlatformStyle.isWindows;
    Widget item(int i) => _SidebarItem(
      tab: tabs[i],
      selected: i == index,
      expanded: expanded,
      fluent: fluent,
      onTap: () => onSelect(i),
    );
    final last = tabs.length - 1;
    return AnimatedContainer(
      duration: Motion.scaled(context, Motion.base),
      curve: Motion.easeInOut,
      width: expanded ? (fluent ? 280 : 248) : (fluent ? 56 : 72),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        right: false,
        child: _FitOrScroll(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: fluent ? 4 : 8,
              vertical: fluent ? 8 : 14,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    expanded ? 12 : 0,
                    4,
                    0,
                    fluent ? 12 : 18,
                  ),
                  child: Row(
                    mainAxisAlignment: expanded
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      BrandSeal(size: fluent ? 28 : 34),
                      if (expanded) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Shaddai Reader',
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            softWrap: false,
                            style: AppText.body(
                              size: fluent ? 13 : 14,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                for (var i = 0; i < last; i++) item(i),
                const Spacer(),
                if (fluent)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Divider(color: AppColors.border, height: 1),
                  ),
                item(last),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  final _Tab tab;
  final bool selected;
  final bool expanded;
  final bool fluent;
  final VoidCallback onTap;
  const _SidebarItem({
    required this.tab,
    required this.selected,
    required this.expanded,
    required this.fluent,
    required this.onTap,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final radius = BorderRadius.circular(w.fluent ? 4 : 10);
    // Selected is full ink plus the violet bar (DESIGN.md "Tab bar"), no
    // tinted pill behind it; fills are only for hover and press.
    final fill = _down
        ? AppColors.fillSubtle
        : _hover
        ? AppColors.fillHover
        : Colors.transparent;
    final color = w.selected ? AppColors.text : AppColors.text60;
    final row = Semantics(
      button: true,
      selected: w.selected,
      label: w.tab.label,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _down = true),
            onTapCancel: () => setState(() => _down = false),
            onTapUp: (_) => setState(() => _down = false),
            onTap: w.onTap,
            child: AnimatedContainer(
              duration: Motion.scaled(context, Motion.fast),
              curve: Motion.easeOut,
              height: w.fluent ? 40 : 44,
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(color: fill, borderRadius: radius),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Fluent's selection mark: a short accent bar at the
                  // leading edge. The web sidebar uses the accent fill.
                  if (w.fluent)
                    AnimatedOpacity(
                      opacity: w.selected ? 1 : 0,
                      duration: Motion.scaled(context, Motion.fast),
                      child: Container(
                        width: 3,
                        height: 16,
                        decoration: BoxDecoration(
                          color: AppColors.accentLink,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: w.expanded ? 14 : 0,
                    ),
                    child: Row(
                      mainAxisAlignment: w.expanded
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.center,
                      children: [
                        Icon(
                          w.selected ? w.tab.selectedIcon : w.tab.icon,
                          size: w.fluent ? 18 : 20,
                          color: w.selected && !w.fluent
                              ? AppColors.accentSoft
                              : color,
                        ),
                        if (w.expanded) ...[
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              w.tab.label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.clip,
                              style: AppText.body(
                                size: w.fluent ? 13.5 : 14,
                                weight: w.selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return w.expanded ? row : Tooltip(message: w.tab.label, child: row);
  }
}

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
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.fast,
    value: 1,
  );

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
      opacity: CurvedAnimation(
        parent: _c,
        curve: Motion.easeOut,
      ).drive(Tween(begin: 0.55, end: 1)),
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
  const _BottomBar({
    required this.tabs,
    required this.index,
    required this.onSelect,
  });

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
          child: LayoutBuilder(
            builder: (context, c) {
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
                            icon: index == i
                                ? tabs[i].selectedIcon
                                : tabs[i].icon,
                            label: tabs[i].label,
                            selected: index == i,
                            onTap: () => onSelect(i),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
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
  const _SideRail({
    required this.tabs,
    required this.index,
    required this.onSelect,
  });

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
        child: _FitOrScroll(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
            child: Column(
              children: [
                const BrandSeal(size: 44),
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
                                icon: index == i
                                    ? tabs[i].selectedIcon
                                    : tabs[i].icon,
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
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
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
                  Text(
                    label,
                    style: AppText.body(
                      size: 10.5,
                      weight: FontWeight.w600,
                      color: c,
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
            position: Tween(
              begin: const Offset(0, 0.3),
              end: Offset.zero,
            ).animate(anim),
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

/// What the now-reading bar shows of a series: its title and cover.
typedef _SeriesLook = ({
  String title,
  String? cover,
  Map<String, String> headers,
});

class _NowReadingBarState extends ConsumerState<_NowReadingBar> {
  String? _seriesId;
  Future<_SeriesLook?>? _series;

  // History stores the chapter, not the series - look the series up once
  // per series (its title and cover) rather than on every rebuild.
  Future<_SeriesLook?> _seriesFor(String? serverId, String seriesId) async {
    try {
      final backend = await ref.read(backendForServerProvider(serverId).future);
      if (backend == null) return null;
      final s = await backend.getSeries(seriesId);
      return (
        title: s.title,
        cover: s.thumbnailUrl,
        headers: backend.imageHeaders,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    if (_seriesId != e.seriesId) {
      _seriesId = e.seriesId;
      _series = _seriesFor(e.serverId, e.seriesId);
    }
    final number = formatChapterNumber(e.bookNumber);

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
                    '/read/${Uri.encodeComponent(e.bookId)}?page=${e.lastPage}',
                  );
                },
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.only(left: 6, right: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.text, width: 2),
                  ),
                  child: FutureBuilder<_SeriesLook?>(
                    future: _series,
                    builder: (context, snap) => Row(
                      children: [
                        // The cover, as DESIGN.md's now-reading pill asks for:
                        // the book you are in, recognisable at a glance.
                        SizedBox(
                          width: 30,
                          height: 42,
                          child: SeriesCover(
                            imageUrl: snap.data?.cover,
                            headers: snap.data?.headers ?? const {},
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                snap.data?.title ?? e.bookTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.body(
                                  size: 13.5,
                                  weight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Ch. $number · page ${e.lastPage + 1} of ${e.pageCount}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.mono(
                                  size: 9.5,
                                  color: AppColors.text60,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Dismiss',
                          icon: Icon(
                            Icons.close,
                            size: 18,
                            color: AppColors.text60,
                          ),
                          onPressed: () =>
                              ref
                                  .read(nowReadingDismissedProvider.notifier)
                                  .state = e
                                  .timestamp,
                        ),
                      ],
                    ),
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
