import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../shared/ink_chip.dart';
import 'guide_demos.dart';

const _seenKey = 'guide_seen';

/// Opens the guide the first time someone reaches Home with a server.
Future<void> showGuideOnce(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_seenKey) ?? false) return;
  await prefs.setBool(_seenKey, true);
  if (context.mounted) context.push('/guide');
}

typedef _Step = ({
  IconData icon,
  String title,
  String about,
  String task,
  ({String label, String route})? showMe,
  Widget Function(VoidCallback done) demo,
});

final List<_Step> _steps = [
  (
    icon: Icons.home_outlined,
    title: 'Five tabs, five jobs',
    about: 'Everything here comes from a home server, not a store, and your '
        'place follows you to every device you sign in on. The app is five '
        'tabs along the bottom (or down the side on a tablet).',
    task: 'Tap all five tabs to see what each one is for.',
    showMe: null,
    demo: (done) => TabsDemo(onDone: done),
  ),
  (
    icon: Icons.search_rounded,
    title: 'Find something to read',
    about: 'Search looks across every source at once. Add a result and choose '
        'the category it goes in. Already reading it somewhere else? Your '
        'place comes along. Nothing found? Ask for it, and follow it under '
        'Settings → My requests.',
    task: 'Search for a title, add it and pick a category.',
    showMe: null,
    demo: (done) => SearchDemo(onDone: done),
  ),
  (
    icon: Icons.format_list_bulleted_rounded,
    title: 'A title page',
    about: 'Chapters are listed newest first (Settings → Newest chapters first '
        'changes that). Tap one to read it; press and hold for more. The ⋯ '
        'button holds Sources, where the backups for a title live, plus Stop '
        'reading and Remove from library.',
    task: 'Press and hold a chapter, then mark it as read.',
    showMe: null,
    demo: (done) => ChapterDemo(onDone: done),
  ),
  (
    icon: Icons.menu_book_outlined,
    title: 'Reading',
    about: 'The page fills the screen. Tap the sides to turn, the middle for '
        'the controls. Reach the end of a chapter and it is marked read, then '
        'the next one starts.',
    task: 'Turn a page, then bring up the controls.',
    showMe: null,
    demo: (done) => PageTurnDemo(onDone: done),
  ),
  (
    icon: Icons.view_day_outlined,
    title: 'Three ways to read',
    about: 'Switch the mode from the reader\'s controls. Each title remembers '
        'the one you picked for it.',
    task: 'Try all three modes.',
    showMe: null,
    demo: (done) => ModesDemo(onDone: done),
  ),
  (
    icon: Icons.download_outlined,
    title: 'Reading offline',
    about: 'Download chapters from a title page and read them with no '
        'connection. If a title\'s source is down, the chapter comes from one '
        'of its backup sources instead, and the reader says so.',
    task: 'Download a chapter.',
    showMe: (label: 'Open Downloads', route: '/settings/downloads'),
    demo: (done) => DownloadDemo(onDone: done),
  ),
  (
    icon: Icons.sync_rounded,
    title: 'Your place, everywhere',
    about: 'Sign in on any device and your library, history and settings '
        'follow. Syncing happens on its own; tap the account card at the top '
        'of Settings to sync now. Sign out is at the bottom of Settings.',
    task: 'Sync, and watch the tablet catch up with the phone.',
    showMe: null,
    demo: (done) => SyncDemo(onDone: done),
  ),
  (
    icon: Icons.bug_report_outlined,
    title: 'Something not right?',
    about: 'Report a problem sends what you write, a screenshot of the screen '
        'and recent logs to the developer. Replies show up under Settings → '
        'Diagnostics & reports.',
    task: 'Turn on the report button, then press it.',
    showMe: (label: 'Open Diagnostics', route: '/debug'),
    demo: (done) => ReportDemo(onDone: done),
  ),
];

/// A hands-on tour for someone opening the app for the first time: each
/// step has a working stand-in for the real screen to try. Also under
/// Settings → How to use Shaddai Reader.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  final _controller = PageController();
  final _done = <int>{};
  var _index = 0;

  /// The steps, then the summary.
  int get _pageCount => _steps.length + 1;
  bool get _onSummary => _index == _steps.length;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() => context.canPop() ? context.pop() : context.go('/');

  void _goTo(int i) => _controller.animateToPage(
        i,
        duration: Motion.scaled(context, Motion.base),
        curve: Motion.easeOut,
      );

  void _next() => _onSummary ? _close() : _goTo(_index + 1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 8, 0),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        _onSummary
                            ? '${_done.length} OF ${_steps.length} TRIED'
                            : 'STEP ${_index + 1} OF ${_steps.length}',
                        style: AppText.sectionLabel(),
                      ),
                    ),
                    TextButton(
                      onPressed: _close,
                      child: Text(_onSummary ? 'Close' : 'Skip',
                          style: AppText.body(size: 15, color: AppColors.accentLink)),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Semantics(
                    label: '${_done.length} of ${_steps.length} steps done',
                    child: Row(children: [
                      for (var i = 0; i < _steps.length; i++)
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _goTo(i),
                            child: AnimatedContainer(
                              duration: Motion.scaled(context, Motion.fast),
                              height: 6,
                              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                              decoration: BoxDecoration(
                                color: _done.contains(i) ? AppColors.accent : AppColors.track,
                                borderRadius: BorderRadius.circular(999),
                                border: i == _index
                                    ? Border.all(color: AppColors.text, width: 1.5)
                                    : null,
                              ),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pageCount,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => i == _steps.length
                        ? _Summary(done: _done, onOpen: _goTo)
                        : _StepPage(
                            step: _steps[i],
                            done: _done.contains(i),
                            onDone: () {
                              if (_done.add(i)) setState(() {});
                            },
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                  child: Row(children: [
                    if (_index > 0) ...[
                      Expanded(
                        child: InkButton(label: 'Back', onTap: () => _goTo(_index - 1)),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: InkButton(
                        filled: true,
                        label: _onSummary
                            ? 'Start reading'
                            : (_done.contains(_index) ? 'Next' : 'Skip this step'),
                        onTap: _next,
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepPage extends StatelessWidget {
  final _Step step;
  final bool done;
  final VoidCallback onDone;
  const _StepPage({required this.step, required this.done, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final showMe = step.showMe;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderStrong, width: 2),
              ),
              child: Icon(step.icon, size: 24, color: AppColors.accentLink),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(step.title, style: AppText.largeTitle(size: 26))),
          ]),
          const SizedBox(height: 14),
          Text(step.about, style: AppText.body(size: 15, color: AppColors.text)),
          const SizedBox(height: 20),
          Row(children: [
            Text('TRY IT', style: AppText.sectionLabel()),
            const Spacer(),
            AnimatedOpacity(
              opacity: done ? 1 : 0,
              duration: Motion.scaled(context, Motion.fast),
              child: Row(children: [
                Icon(Icons.check_circle_rounded, size: 16, color: AppColors.accentLink),
                const SizedBox(width: 4),
                Text('DONE', style: AppText.mono(size: 11, color: AppColors.accentLink)),
              ]),
            ),
          ]),
          const SizedBox(height: 4),
          Text(step.task, style: AppText.body(size: 14, color: AppColors.text60)),
          const SizedBox(height: 12),
          step.demo(onDone),
          if (showMe != null) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: InkButton(
                icon: Icons.open_in_new_rounded,
                label: showMe.label,
                height: 44,
                // Opens the real screen on top; Back returns to the guide.
                onTap: () => context.push(showMe.route),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final Set<int> done;
  final ValueChanged<int> onOpen;
  const _Summary({required this.done, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final all = done.length == _steps.length;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(all ? 'You\'re all set' : 'Nearly there', style: AppText.largeTitle(size: 26)),
        const SizedBox(height: 8),
        Text(
          all
              ? 'You\'ve tried everything. Come back any time from Settings → '
                  'How to use Shaddai Reader.'
              : 'Tap a step to try it, or start reading now. The guide stays in '
                  'Settings → How to use Shaddai Reader.',
          style: AppText.body(size: 15, color: AppColors.text60),
        ),
        const SizedBox(height: 16),
        DemoFrame(
          child: Column(children: [
            for (final (i, s) in _steps.indexed) ...[
              ListTile(
                onTap: () => onOpen(i),
                leading: Icon(
                  done.contains(i) ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                  color: done.contains(i) ? AppColors.accentLink : AppColors.text45,
                ),
                title: Text(s.title, style: AppText.body(size: 14.5)),
                trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text45),
              ),
              if (i != _steps.length - 1) Divider(height: 1, color: AppColors.border),
            ],
          ]),
        ),
      ]),
    );
  }
}
