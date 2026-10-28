import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/brand_seal.dart';
import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../backends/suwayomi/suwayomi_backend.dart';
import '../../core/backend/reader_backend.dart';
import '../../core/updates/updates.dart';
import '../home/home_feed.dart' show homeFeedProvider, lastReadByKey, seriesKey;
import '../shared/back_button.dart';
import '../shared/error_state.dart';
import '../shared/ink_chip.dart';
import '../shared/series_cover.dart';

class UpdatesFeed {
  final List<UpdateGroup> groups;
  final Map<String, ReaderBackend> backends;

  /// When Suwayomi last looked for new chapters; null when unknown.
  final DateTime? lastChecked;
  const UpdatesFeed({required this.groups, required this.backends, this.lastChecked});
}

/// New chapters of series you are reading or have finished, from every
/// server. Suwayomi knows what you've read, so all its library titles with
/// a chapter read count; on Komga it's series in your History. A server
/// that doesn't answer just has no rows (Home already says it's down).
final updatesProvider = FutureProvider<UpdatesFeed>((ref) async {
  final backends = await ref.watch(allBackendsProvider.future);
  ref.watch(historyRevisionProvider);
  final read = lastReadByKey(
    ref.read(historyStoreProvider).list(),
    ref.read(activeServerIdProvider),
  ).keys.toSet();

  final chapters = <UpdateChapter>[];
  final suwayomi = <String>{};
  DateTime? lastChecked;
  await Future.wait(backends.map((b) async {
    final id = b.config.id;
    try {
      if (b is SuwayomiBackend) {
        suwayomi.add(id);
        for (final u in await b.recentUpdates()) {
          chapters.add(UpdateChapter(serverId: id, seriesTitle: u.seriesTitle, book: u.book));
        }
        final t = await b.lastUpdateCheck();
        if (t != null && (lastChecked == null || t.isAfter(lastChecked!))) lastChecked = t;
      } else if (b.config.type == ServerType.komga) {
        final followed = (await b.recentlyAdded())
            .where((bk) => read.contains(seriesKey(id, bk.seriesId)))
            .toList();
        final titles = <String, String>{};
        for (final sid in followed.map((bk) => bk.seriesId).toSet()) {
          titles[sid] = (await b.getSeries(sid)).title;
        }
        for (final bk in followed) {
          chapters.add(UpdateChapter(serverId: id, seriesTitle: titles[bk.seriesId]!, book: bk));
        }
      }
    } catch (_) {}
  }));

  return UpdatesFeed(
    groups: groupUpdates(chapters,
        follows: (server, series) =>
            suwayomi.contains(server) || read.contains(seriesKey(server, series))),
    backends: {for (final b in backends) b.config.id: b},
    lastChecked: lastChecked,
  );
});

Future<void> _open(BuildContext context, WidgetRef ref, UpdateGroup g) async {
  await activateServer(ref, g.serverId);
  if (context.mounted) context.push('/read/${Uri.encodeComponent(g.next.id)}');
}

/// The full list, newest first, under day headings. Pull to re-read; the
/// owner can also ask Suwayomi to check its sources now.
class UpdatesScreen extends ConsumerStatefulWidget {
  const UpdatesScreen({super.key});

  @override
  ConsumerState<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends ConsumerState<UpdatesScreen> {
  Timer? _poll;
  ({int done, int total})? _checking;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Starts a library update on every Suwayomi server and follows it; the
  /// list re-reads when they are all done.
  Future<void> _checkNow(List<SuwayomiBackend> servers) async {
    setState(() => _checking = (done: 0, total: 0));
    try {
      for (final s in servers) {
        await s.startLibraryUpdate();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _checking = null);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't start: ${AppErrorState.errorHeadline(e)}")));
      return;
    }
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      var done = 0, total = 0, running = false;
      for (final s in servers) {
        try {
          final p = await s.libraryUpdateProgress();
          done += p.done;
          total += p.total;
          running |= p.running;
        } catch (_) {}
      }
      if (!mounted) return;
      if (running) {
        setState(() => _checking = (done: done, total: total));
      } else {
        _poll?.cancel();
        setState(() => _checking = null);
        ref.invalidate(updatesProvider);
        ref.invalidate(homeFeedProvider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(updatesProvider);
    final owner = ref.watch(isOwnerProvider);
    final now = DateTime.now();
    final feed = async.valueOrNull;
    final checkable = feed?.backends.values.whereType<SuwayomiBackend>().toList() ?? const [];

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: RefreshIndicator.adaptive(
              color: AppColors.accent,
              onRefresh: () => ref.refresh(updatesProvider.future),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                      child: Row(children: [
                        const AppBackButton(),
                        const SizedBox(width: 12),
                        Text('Updates', style: AppText.largeTitle(size: 24)),
                      ]),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: _CheckBar(
                        lastChecked: feed?.lastChecked,
                        now: now,
                        checking: _checking,
                        onCheck: owner && checkable.isNotEmpty ? () => _checkNow(checkable) : null,
                      ),
                    ),
                  ),
                  ...async.when(
                    loading: () => [
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator.adaptive()),
                      ),
                    ],
                    error: (e, _) => [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: AppErrorState(error: e, onRetry: () => ref.invalidate(updatesProvider)),
                      ),
                    ],
                    data: (feed) => feed.groups.isEmpty
                        ? [
                            const SliverFillRemaining(
                              hasScrollBody: false,
                              child: EmptyState(
                                title: 'No new chapters',
                                message:
                                    "New chapters of series you're reading or have finished show up here.",
                              ),
                            ),
                          ]
                        : [
                            for (final (day, groups) in _byDay(feed.groups)) ...[
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                                  child: Text(dayLabel(day, now), style: AppText.sectionLabel()),
                                ),
                              ),
                              SliverList.list(children: [
                                for (final g in groups)
                                  UpdateRow(group: g, backend: feed.backends[g.serverId]!, now: now),
                              ]),
                            ],
                            const SliverToBoxAdapter(child: SizedBox(height: 120)),
                          ],
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

List<(DateTime, List<UpdateGroup>)> _byDay(List<UpdateGroup> groups) {
  final out = <(DateTime, List<UpdateGroup>)>[];
  for (final g in groups) {
    if (out.isEmpty || out.last.$1 != g.day) out.add((g.day, []));
    out.last.$2.add(g);
  }
  return out;
}

class _CheckBar extends StatelessWidget {
  final DateTime? lastChecked;
  final DateTime now;
  final ({int done, int total})? checking;
  final VoidCallback? onCheck;
  const _CheckBar({required this.lastChecked, required this.now, this.checking, this.onCheck});

  @override
  Widget build(BuildContext context) {
    final c = checking;
    final status = c != null
        ? (c.total == 0 ? 'STARTING THE CHECK…' : 'CHECKING ${c.done} OF ${c.total}')
        : lastChecked == null
            ? null
            : 'LAST CHECKED ${agoLabel(lastChecked!, now)}';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 10,
        children: [
          if (status != null) Text(status, style: AppText.mono(size: 10.5)),
          if (onCheck != null)
            InkButton(
              filled: true,
              icon: Icons.refresh_rounded,
              label: 'Check for updates',
              height: 42,
              onTap: c == null ? onCheck : null,
            ),
        ],
      ),
      if (c != null && c.total > 0) ...[
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: c.done / c.total,
          minHeight: 4,
          color: AppColors.accent,
          backgroundColor: AppColors.track,
        ),
      ],
    ]);
  }
}

/// One series' new chapters on one day. Tapping opens the oldest unread.
class UpdateRow extends ConsumerWidget {
  final UpdateGroup group;
  final ReaderBackend backend;
  final DateTime now;
  const UpdateRow({super.key, required this.group, required this.backend, required this.now});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = group;
    final facts = '${chapterRange(g.chapters)} · ${agoLabel(g.latestAt, now)}';
    return Semantics(
      button: true,
      label: '${g.seriesTitle}, ${facts.toLowerCase()}${g.hasUnread ? ', unread' : ''}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => _open(context, ref, g),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(children: [
              SizedBox(
                width: 44,
                height: 66,
                child: SeriesCover(
                  imageUrl: backend.thumbnailUrlForSeries(g.seriesId),
                  headers: backend.imageHeaders,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(g.seriesTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(size: 14.5, weight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(facts,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.mono(size: 10.5)),
                ]),
              ),
              if (g.hasUnread) ...[
                const SizedBox(width: 12),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Home's strip: the latest few rows and a way to the full list. Hidden
/// while there's nothing new, so it never adds an empty block. [serverId]
/// follows Home's source filter.
class UpdatesStrip extends ConsumerWidget {
  final String? serverId;
  const UpdatesStrip({super.key, this.serverId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(updatesProvider).valueOrNull;
    if (feed == null) return const SizedBox.shrink();
    // One row per series here (its newest day); the full screen keeps
    // every day, so a weekly series doesn't fill the whole strip.
    final seen = <String>{};
    final groups = feed.groups
        .where((g) => serverId == null || g.serverId == serverId)
        .where((g) => seen.add('${g.serverId}|${g.seriesId}'))
        .take(4)
        .toList();
    if (groups.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 12, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Updates', style: AppText.heading(size: 17)),
            TextButton(
              onPressed: () => context.push('/updates'),
              child: Text('See all',
                  style: AppText.body(
                      size: 13, weight: FontWeight.w500, color: AppColors.accentLink)),
            ),
          ],
        ),
      ),
      for (final g in groups) UpdateRow(group: g, backend: feed.backends[g.serverId]!, now: now),
    ]);
  }
}
