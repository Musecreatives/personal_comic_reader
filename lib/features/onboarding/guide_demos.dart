import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../shared/ink_chip.dart';

/// Hands-on stand-ins for the real screens, used by the guide. Each one
/// calls [onDone] once the person has done the thing it teaches; none of
/// them touch a server or the library.

/// A drawn frame around a demo, like a screen in miniature.
class DemoFrame extends StatelessWidget {
  final Widget child;
  final double? height;
  const DemoFrame({super.key, required this.child, this.height});

  @override
  // A Material, not a decorated box, so taps inside show their ripple.
  Widget build(BuildContext context) => Material(
        color: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.text.withValues(alpha: 0.7), width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(height: height, child: child),
      );
}

/// A line under a demo that ticks when its part is done.
class DemoCheck extends StatelessWidget {
  final String label;
  final bool done;
  const DemoCheck(this.label, this.done, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              size: 18, color: done ? AppColors.accentLink : AppColors.text45),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: AppText.body(
                    size: 13.5, color: done ? AppColors.text : AppColors.text60)),
          ),
        ]),
      );
}

const _tabs = [
  (Icons.home_outlined, 'Home', 'Picks up where you left off and shows titles with new chapters.'),
  (Icons.search_rounded, 'Search', 'Looks across every source at once, and asks for what nobody has yet.'),
  (Icons.menu_book_outlined, 'Library', 'Everything you follow, sorted into your categories.'),
  (Icons.history_rounded, 'History', 'What you read lately, on every device you sign in on.'),
  (Icons.settings_outlined, 'Settings', 'Downloads, appearance, help, and signing out.'),
];

/// Tap all five tabs.
class TabsDemo extends StatefulWidget {
  final VoidCallback onDone;
  const TabsDemo({super.key, required this.onDone});

  @override
  State<TabsDemo> createState() => _TabsDemoState();
}

class _TabsDemoState extends State<TabsDemo> {
  final _seen = <int>{};
  int? _at;

  void _tap(int i) {
    setState(() {
      _at = i;
      _seen.add(i);
    });
    if (_seen.length == _tabs.length) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final at = _at;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DemoFrame(
        child: Column(children: [
          SizedBox(
            height: 92,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text(
                  at == null ? 'Tap a tab below.' : _tabs[at].$3,
                  textAlign: TextAlign.center,
                  style: AppText.body(size: 14.5),
                ),
              ),
            ),
          ),
          Divider(height: 1, color: AppColors.border),
          Row(children: [
            for (final (i, t) in _tabs.indexed)
              Expanded(
                child: InkWell(
                  onTap: () => _tap(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(children: [
                      Container(
                        height: 3,
                        width: 22,
                        color: at == i ? AppColors.accent : Colors.transparent,
                      ),
                      const SizedBox(height: 6),
                      Icon(t.$1, size: 22, color: at == i ? AppColors.text : AppColors.text60),
                      const SizedBox(height: 4),
                      FittedBox(
                        child: Text(t.$2,
                            style: AppText.body(
                                size: 11.5, color: at == i ? AppColors.text : AppColors.text60)),
                      ),
                      const SizedBox(height: 2),
                      Icon(Icons.check_rounded,
                          size: 12,
                          color: _seen.contains(i) ? AppColors.accentLink : Colors.transparent),
                    ]),
                  ),
                ),
              ),
          ]),
        ]),
      ),
      DemoCheck('Tapped ${_seen.length} of ${_tabs.length} tabs', _seen.length == _tabs.length),
    ]);
  }
}

/// Search, add a result, pick its category.
class SearchDemo extends StatefulWidget {
  final VoidCallback onDone;
  const SearchDemo({super.key, required this.onDone});

  @override
  State<SearchDemo> createState() => _SearchDemoState();
}

class _SearchDemoState extends State<SearchDemo> {
  final _query = TextEditingController();
  String? _adding;
  String? _addedTo;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DemoFrame(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Type a title',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in const ['Solo Leveling', 'One Piece', 'Mount Hua'])
                InkChip(
                  label: s,
                  selected: q == s,
                  onTap: () => setState(() => _query.text = s),
                ),
            ]),
            if (q.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final source in const ['MANGAK', 'MANGA DEMON'])
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    Container(
                      width: 34,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.page,
                        border: Border.all(color: AppColors.text60, width: 2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(q, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: AppText.body(size: 14, weight: FontWeight.w600)),
                        Text(source, style: AppText.mono(size: 10)),
                      ]),
                    ),
                    if (_addedTo != null && _adding == source)
                      Text('IN ${_addedTo!.toUpperCase()}',
                          style: AppText.mono(size: 10.5, color: AppColors.accentLink))
                    else
                      TextButton(
                        onPressed: _addedTo == null
                            ? () => setState(() => _adding = source)
                            : null,
                        child: const Text('Add'),
                      ),
                  ]),
                ),
            ],
            if (_adding != null && _addedTo == null) ...[
              const SizedBox(height: 10),
              Text('Which category?', style: AppText.body(size: 13, color: AppColors.text60)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in const ['Default', 'Murim', 'Romance'])
                  InkChip(
                    label: c,
                    selected: false,
                    onTap: () {
                      setState(() => _addedTo = c);
                      widget.onDone();
                    },
                  ),
              ]),
            ],
          ]),
        ),
      ),
      DemoCheck('Searched for a title', q.isNotEmpty),
      DemoCheck('Added it and picked its category', _addedTo != null),
    ]);
  }
}

/// Press and hold a chapter, then mark it read.
class ChapterDemo extends StatefulWidget {
  final VoidCallback onDone;
  const ChapterDemo({super.key, required this.onDone});

  @override
  State<ChapterDemo> createState() => _ChapterDemoState();
}

class _ChapterDemoState extends State<ChapterDemo> {
  final _read = <int>{};
  int? _menu;
  String? _note;

  void _mark(Iterable<int> chapters, String note) {
    setState(() {
      _read.addAll(chapters);
      _menu = null;
      _note = note;
    });
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DemoFrame(
        child: Column(children: [
          for (final n in const [4, 3, 2, 1]) ...[
            Semantics(
              onLongPressHint: 'Show chapter actions',
              child: InkWell(
                onLongPress: () => setState(() => _menu = n),
                onTap: () => setState(() => _note = 'A tap opens the chapter. Press and hold instead.'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(children: [
                    Expanded(
                      child: Text('Chapter $n',
                          style: AppText.body(
                              size: 14.5,
                              color: _read.contains(n) ? AppColors.text45 : AppColors.text)),
                    ),
                    if (_read.contains(n))
                      Text('READ', style: AppText.mono(size: 10, color: AppColors.text45)),
                  ]),
                ),
              ),
            ),
            if (_menu == n)
              Container(
                color: AppColors.page,
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                child: Wrap(spacing: 4, children: [
                  TextButton(onPressed: () => _mark([n], 'Chapter $n is read.'), child: const Text('Mark as read')),
                  TextButton(
                    onPressed: () => _mark([for (var i = 1; i <= n; i++) i], 'Chapters 1 to $n are read.'),
                    child: const Text('Mark all before as read'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _menu = null;
                      _note = 'Downloading saves it for reading offline.';
                    }),
                    child: const Text('Download'),
                  ),
                ]),
              ),
            if (n != 1) Divider(height: 1, color: AppColors.border),
          ],
        ]),
      ),
      if (_note != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_note!, style: AppText.body(size: 13, color: AppColors.text60)),
        ),
      DemoCheck('Pressed and held a chapter', _menu != null || _read.isNotEmpty),
      DemoCheck('Marked one as read', _read.isNotEmpty),
    ]);
  }
}

/// Turn a page, show the controls.
class PageTurnDemo extends StatefulWidget {
  final VoidCallback onDone;
  const PageTurnDemo({super.key, required this.onDone});

  @override
  State<PageTurnDemo> createState() => _PageTurnDemoState();
}

class _PageTurnDemoState extends State<PageTurnDemo> {
  static const _pages = 8;
  var _page = 1;
  var _controls = false;
  var _turned = false;
  var _toggled = false;

  void _update(VoidCallback f) {
    setState(f);
    if (_turned && _toggled) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final fade = Motion.scaled(context, Motion.fast);
    Widget zone(String label, VoidCallback onTap) => Expanded(
          child: Semantics(
            button: true,
            label: label,
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DemoFrame(
        height: 250,
        child: Stack(children: [
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.canvas,
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('$_page', style: AppText.largeTitle(size: 56)),
                  Text('PAGE', style: AppText.mono(size: 11, color: AppColors.text60)),
                ]),
              ),
            ),
          ),
          Positioned.fill(
            child: Row(children: [
              zone('Previous page', () => _update(() {
                    if (_page > 1) _page--;
                    _turned = true;
                  })),
              zone('Show or hide the controls', () => _update(() {
                    _controls = !_controls;
                    _toggled = true;
                  })),
              zone('Next page', () => _update(() {
                    if (_page < _pages) _page++;
                    _turned = true;
                  })),
            ]),
          ),
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: fade,
              child: Column(children: [
                Container(
                  color: AppColors.card,
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    Icon(Icons.arrow_back_rounded, size: 18, color: AppColors.text),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Solo Leveling · Ch. 12', style: AppText.body(size: 13))),
                  ]),
                ),
                const Spacer(),
                Container(
                  color: AppColors.card,
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: _page / _pages,
                        color: AppColors.accent,
                        backgroundColor: AppColors.track,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('$_page / $_pages', style: AppText.mono(size: 11)),
                  ]),
                ),
              ]),
            ),
          ),
          IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedOpacity(
                opacity: _controls ? 0 : 1,
                duration: fade,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text('BACK  ·  CONTROLS  ·  NEXT',
                      style: AppText.mono(size: 10, color: AppColors.text30)),
                ),
              ),
            ),
          ),
        ]),
      ),
      DemoCheck('Tapped the right side to turn the page', _turned),
      DemoCheck('Tapped the middle to show the controls', _toggled),
    ]);
  }
}

enum _Mode { webtoon, paged, double }

/// Try all three reading modes.
class ModesDemo extends StatefulWidget {
  final VoidCallback onDone;
  const ModesDemo({super.key, required this.onDone});

  @override
  State<ModesDemo> createState() => _ModesDemoState();
}

class _ModesDemoState extends State<ModesDemo> {
  var _mode = _Mode.webtoon;
  final _tried = <_Mode>{_Mode.webtoon};

  static const _about = {
    _Mode.webtoon: 'Webtoon: one long strip you scroll down. Best for manhwa.',
    _Mode.paged: 'Paged: one page at a time, tap or swipe to turn.',
    _Mode.double: 'Double: two pages side by side, like an open book. Turn your device sideways.',
  };

  Widget _page(String label) => Container(
        decoration: BoxDecoration(
          color: AppColors.page,
          border: Border.all(color: AppColors.text60, width: 2),
        ),
        alignment: Alignment.center,
        child: Text(label, style: AppText.mono(size: 11, color: AppColors.text60)),
      );

  @override
  Widget build(BuildContext context) {
    final preview = switch (_mode) {
      _Mode.webtoon => ListView(
          padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 10),
          children: [
            for (var i = 1; i <= 5; i++)
              SizedBox(height: 110, child: _page('PANEL $i')),
          ],
        ),
      _Mode.paged => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 70, vertical: 14),
          child: _page('PAGE 1'),
        ),
      _Mode.double => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Row(children: [
            Expanded(child: _page('PAGE 1')),
            const SizedBox(width: 4),
            Expanded(child: _page('PAGE 2')),
          ]),
        ),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in _Mode.values)
          InkChip(
            label: switch (m) {
              _Mode.webtoon => 'Webtoon',
              _Mode.paged => 'Paged',
              _Mode.double => 'Double',
            },
            selected: _mode == m,
            onTap: () {
              setState(() {
                _mode = m;
                _tried.add(m);
              });
              if (_tried.length == _Mode.values.length) widget.onDone();
            },
          ),
      ]),
      const SizedBox(height: 10),
      DemoFrame(height: 210, child: ColoredBox(color: AppColors.canvas, child: preview)),
      const SizedBox(height: 8),
      Text(_about[_mode]!, style: AppText.body(size: 13.5, color: AppColors.text60)),
      DemoCheck('Tried ${_tried.length} of 3 modes', _tried.length == _Mode.values.length),
    ]);
  }
}

/// Download a chapter.
class DownloadDemo extends StatefulWidget {
  final VoidCallback onDone;
  const DownloadDemo({super.key, required this.onDone});

  @override
  State<DownloadDemo> createState() => _DownloadDemoState();
}

class _DownloadDemoState extends State<DownloadDemo> with SingleTickerProviderStateMixin {
  late final _progress = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
  var _wifiOnly = true;

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _start() {
    if (_progress.isAnimating || _progress.isCompleted) return;
    if (Motion.reduced(context)) {
      _progress.value = 1;
      widget.onDone();
    } else {
      _progress.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DemoFrame(
        child: AnimatedBuilder(
          animation: _progress,
          builder: (context, _) {
            final v = _progress.value;
            final done = _progress.isCompleted;
            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Chapter 12', style: AppText.body(size: 14.5)),
                      Text(
                        done
                            ? 'ON THIS DEVICE'
                            : v > 0
                                ? 'DOWNLOADING · ${(v * 24).round()} OF 24 PAGES'
                                : '24 PAGES',
                        style: AppText.mono(size: 10, color: done ? AppColors.accentLink : AppColors.text60),
                      ),
                    ]),
                  ),
                  IconButton(
                    tooltip: done ? 'Downloaded' : 'Download',
                    onPressed: done ? null : _start,
                    icon: Icon(
                      done ? Icons.download_done_rounded : Icons.download_rounded,
                      color: done ? AppColors.accentLink : AppColors.text,
                    ),
                  ),
                ]),
                if (v > 0 && !done)
                  LinearProgressIndicator(
                      value: v, color: AppColors.accent, backgroundColor: AppColors.track),
              ]),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: Text('Download on Wi-Fi only', style: AppText.body(size: 14))),
        Switch.adaptive(value: _wifiOnly, onChanged: (v) => setState(() => _wifiOnly = v)),
      ]),
      DemoCheck('Downloaded a chapter', _progress.isCompleted),
    ]);
  }
}

/// Sync carries your place from one device to the other.
class SyncDemo extends StatefulWidget {
  final VoidCallback onDone;
  const SyncDemo({super.key, required this.onDone});

  @override
  State<SyncDemo> createState() => _SyncDemoState();
}

class _SyncDemoState extends State<SyncDemo> {
  var _syncing = false;
  var _synced = false;

  Future<void> _sync() async {
    if (_syncing || _synced) return;
    setState(() => _syncing = true);
    await Future<void>.delayed(Motion.scaled(context, const Duration(milliseconds: 700)));
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _synced = true;
    });
    widget.onDone();
  }

  Widget _device(IconData icon, String name, String place, bool fresh) => Expanded(
        child: DemoFrame(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Icon(icon, color: AppColors.text60),
              const SizedBox(height: 6),
              Text(name, style: AppText.body(size: 13)),
              const SizedBox(height: 4),
              Text(place,
                  textAlign: TextAlign.center,
                  style: AppText.mono(size: 10, color: fresh ? AppColors.accentLink : AppColors.text60)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        _device(Icons.smartphone_rounded, 'Phone', 'CH. 12 · PAGE 31', false),
        const SizedBox(width: 10),
        _device(Icons.tablet_rounded, 'Tablet', _synced ? 'CH. 12 · PAGE 31' : 'CH. 12 · PAGE 4', _synced),
      ]),
      const SizedBox(height: 10),
      InkButton(
        icon: _synced ? Icons.check_rounded : Icons.sync_rounded,
        label: _syncing ? 'Syncing…' : (_synced ? 'Synced just now' : 'Sync now'),
        onTap: _synced || _syncing ? null : _sync,
      ),
      DemoCheck('Synced, and the tablet caught up with the phone', _synced),
    ]);
  }
}

/// Turn on the report button and press it.
class ReportDemo extends StatefulWidget {
  final VoidCallback onDone;
  const ReportDemo({super.key, required this.onDone});

  @override
  State<ReportDemo> createState() => _ReportDemoState();
}

class _ReportDemoState extends State<ReportDemo> {
  var _on = false;
  var _opened = false;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('Report button on every screen', style: AppText.body(size: 14))),
        Switch.adaptive(value: _on, onChanged: (v) => setState(() => _on = v)),
      ]),
      const SizedBox(height: 8),
      DemoFrame(
        height: 170,
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: _opened
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Report a problem', style: AppText.heading(size: 16)),
                    const SizedBox(height: 6),
                    Text('What happened? A screenshot of this screen and the recent logs go with it.',
                        style: AppText.body(size: 13, color: AppColors.text60)),
                  ])
                : Text(
                    _on ? 'The bug button sits in the corner of every screen.' : 'Any screen in the app.',
                    style: AppText.body(size: 13, color: AppColors.text60)),
          ),
          if (_on && !_opened)
            Positioned(
              right: 12,
              bottom: 12,
              child: FloatingActionButton.small(
                heroTag: null,
                tooltip: 'Report a problem',
                backgroundColor: AppColors.page,
                onPressed: () {
                  setState(() => _opened = true);
                  widget.onDone();
                },
                child: Icon(Icons.bug_report_outlined, color: AppColors.text),
              ),
            ),
        ]),
      ),
      DemoCheck('Turned the button on', _on),
      DemoCheck('Pressed it', _opened),
    ]);
  }
}
