import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../shared/ink_chip.dart';

const _seenKey = 'guide_seen';

/// Opens the guide the first time someone reaches Home with a server.
Future<void> showGuideOnce(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_seenKey) ?? false) return;
  await prefs.setBool(_seenKey, true);
  if (context.mounted) context.push('/guide');
}

typedef _Page = ({IconData icon, String title, List<String> points});

const List<_Page> _pages = [
  (
    icon: Icons.home_outlined,
    title: 'Welcome to Shaddai Reader',
    points: [
      'Everything here comes from a home server, not a store. Your progress follows you to every device you sign in on.',
      'Home picks up where you left off and shows titles with new chapters.',
      'Five tabs along the bottom: Home, Search, Library, History and Settings.',
    ],
  ),
  (
    icon: Icons.search_rounded,
    title: 'Find something to read',
    points: [
      'Search looks across every source at once. Open a result and add it to your library.',
      'Library holds everything you follow. The chips under the search field filter by category.',
      'Already reading it somewhere else? Adding or moving it keeps the chapters you have read.',
    ],
  ),
  (
    icon: Icons.format_list_bulleted_rounded,
    title: 'A title page',
    points: [
      'Chapters are listed newest first. Change that in Settings → Newest chapters first.',
      'Tap a chapter to read it. Press and hold one for Select, Mark as read, Mark all before as read and Download.',
      'The ⋯ button holds Stop reading, Delete downloads and Remove from library.',
    ],
  ),
  (
    icon: Icons.menu_book_outlined,
    title: 'Reading',
    points: [
      'Tap the middle of the page to show or hide the controls. Tap the left or right side to turn the page.',
      'Three modes: Webtoon scrolls down, Paged turns one page at a time, Double shows two side by side (turn your device sideways).',
      'Reach the end of a chapter and it is marked read, then the next one starts.',
    ],
  ),
  (
    icon: Icons.download_outlined,
    title: 'Reading offline',
    points: [
      'Download chapters from a title page to read without a connection.',
      'Settings → Downloads shows the queue and can keep downloads to Wi-Fi.',
    ],
  ),
  (
    icon: Icons.bug_report_outlined,
    title: 'Something not right?',
    points: [
      'Settings → Report a problem sends what you write, a screenshot of the screen and recent logs to the developer.',
      'Turn on Settings → Report button on every screen to report from exactly where it broke.',
      'Replies show up under Settings → Diagnostics & reports.',
    ],
  ),
];

/// A short tour for someone opening the app for the first time; also under
/// Settings → How to use Shaddai Reader.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  final _controller = PageController();
  var _index = 0;

  bool get _last => _index == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() => context.canPop() ? context.pop() : context.go('/');

  void _next() {
    if (_last) return _close();
    _controller.nextPage(
      duration: Motion.scaled(context, Motion.base),
      curve: Motion.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
                    child: TextButton(
                      onPressed: _close,
                      child: Text(
                        'Skip',
                        style: AppText.body(
                          size: 15,
                          color: AppColors.accentLink,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => _GuidePage(page: _pages[i]),
                  ),
                ),
                Semantics(
                  label: 'Page ${_index + 1} of ${_pages.length}',
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        AnimatedContainer(
                          duration: Motion.scaled(context, Motion.fast),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _index ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _index
                                ? AppColors.accent
                                : AppColors.track,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                  child: Row(
                    children: [
                      if (_index > 0)
                        Expanded(
                          child: InkButton(
                            label: 'Back',
                            onTap: () => _controller.previousPage(
                              duration: Motion.scaled(context, Motion.base),
                              curve: Motion.easeOut,
                            ),
                          ),
                        ),
                      if (_index > 0) const SizedBox(width: 10),
                      Expanded(
                        child: InkButton(
                          filled: true,
                          label: _last ? 'Start reading' : 'Next',
                          onTap: _next,
                        ),
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

class _GuidePage extends StatelessWidget {
  final _Page page;
  const _GuidePage({required this.page});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderStrong, width: 2),
            ),
            child: Icon(page.icon, size: 26, color: AppColors.accentLink),
          ),
          const SizedBox(height: 22),
          Text(page.title, style: AppText.largeTitle(size: 28)),
          const SizedBox(height: 18),
          for (final p in page.points)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: 12),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      p,
                      style: AppText.body(size: 15.5, color: AppColors.text),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
