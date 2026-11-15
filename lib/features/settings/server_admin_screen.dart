import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../shared/back_button.dart';

/// Owner only: the server at a glance. Friends and how active they are,
/// requests waiting, each manga source's nightly health check (a blocked
/// one sinks to the end of the preferred order by itself), the order the
/// server looks for alternate sources in, and how far that search has got.
class ServerAdminScreen extends ConsumerStatefulWidget {
  const ServerAdminScreen({super.key});

  @override
  ConsumerState<ServerAdminScreen> createState() => _ServerAdminScreenState();
}

typedef _Data = ({Map<String, dynamic> stats, Map<String, dynamic> health});

class _ServerAdminScreenState extends ConsumerState<ServerAdminScreen> {
  late Future<_Data> _future = _load();
  List<String>? _order;

  Future<_Data> _load() async {
    final client = ref.read(syncClientProvider);
    final results = await Future.wait([client.adminStats(), client.sourceHealth()]);
    _order = null;
    return (stats: results[0], health: results[1]);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _act(Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("That didn't work: $e")));
    }
  }

  Future<void> _reorder(List<String> order, int from, int to) async {
    final next = [...order];
    final moved = next.removeAt(from);
    next.insert(to, moved); // onReorderItem has already allowed for the removal
    setState(() => _order = next);
    await _act(() => ref.read(syncClientProvider).setSourceOrder(next), 'Source order saved');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppScreenHeader(title: 'Server overview', titleSize: 28),
            Expanded(
              child: FutureBuilder<_Data>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: TextButton(
                          onPressed: _reload, child: const Text("Couldn't load the server. Try again")),
                    );
                  }
                  final d = snap.data!;
                  final sources = (d.health['sources'] as List).cast<Map<String, dynamic>>();
                  final order = _order ?? (d.health['order'] as List).cast<String>();
                  final left = [
                    _Overview(stats: d.stats, sources: sources),
                    const SizedBox(height: 24),
                    _People(people: (d.stats['people'] as List).cast<Map<String, dynamic>>()),
                  ];
                  final right = [
                    _SourceHealth(
                      sources: sources,
                      onCheck: () => _act(ref.read(syncClientProvider).runSourceHealth,
                          'Checking every source - pull to refresh in a few minutes'),
                    ),
                    const SizedBox(height: 24),
                    _SourceOrder(
                      order: order,
                      names: {for (final s in sources) s['source_id'] as String: s['name'] as String},
                      onReorder: (from, to) => _reorder(order, from, to),
                    ),
                    const SizedBox(height: 24),
                    _Alternates(
                      counts: (d.stats['alternates'] as Map).cast<String, dynamic>(),
                      onRun: () => _act(
                          () => ref.read(syncClientProvider).findAlternates(again: true),
                          'Looking for alternates across the library again'),
                    ),
                  ];
                  return RefreshIndicator(
                    onRefresh: () async => _reload(),
                    child: LayoutBuilder(builder: (context, box) {
                      final wide = box.maxWidth >= 1000;
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
                        children: wide
                            ? [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: Column(children: left)),
                                    const SizedBox(width: 24),
                                    Expanded(child: Column(children: right)),
                                  ],
                                ),
                              ]
                            : [...left, const SizedBox(height: 24), ...right],
                      );
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A source's health as words and an icon, never colour alone.
({String label, IconData icon, Color color}) sourceStatus(String status) => switch (status) {
      'ok' => (label: 'Working', icon: Icons.check_circle_outline, color: AppColors.suwayomiText),
      'blocked' => (label: 'Blocked', icon: Icons.block, color: AppColors.danger),
      'slow' => (label: 'Slow', icon: Icons.hourglass_bottom, color: AppColors.warningText),
      _ => (label: 'Failing', icon: Icons.error_outline, color: AppColors.warningText),
    };

/// "3 h ago" from a Unix time in seconds.
String agoText(num? unixSeconds, {DateTime? now}) {
  if (unixSeconds == null) return 'never';
  final d = (now ?? DateTime.now())
      .difference(DateTime.fromMillisecondsSinceEpoch((unixSeconds * 1000).round()));
  if (d.inMinutes < 2) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays < 60) return '${d.inDays} d ago';
  return '${d.inDays ~/ 30} months ago';
}

String _shortName(String name) => name.replaceAll(RegExp(r' \((EN|ALL)\)$'), '');

class _Section extends StatelessWidget {
  final String label;
  final Widget? action;
  final Widget child;
  const _Section({required this.label, required this.child, this.action});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(label, style: AppText.sectionLabel())),
            ?action,
          ]),
          const SizedBox(height: 10),
          child,
        ],
      );
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}

class _Overview extends StatelessWidget {
  final Map<String, dynamic> stats;
  final List<Map<String, dynamic>> sources;
  const _Overview({required this.stats, required this.sources});

  @override
  Widget build(BuildContext context) {
    final people = (stats['people'] as List).length;
    final alt = (stats['alternates'] as Map).cast<String, dynamic>();
    final ok = sources.where((s) => s['status'] == 'ok').length;
    final tiles = [
      ('Active this week', '${stats['active_7d']}', 'of $people people'),
      ('Requests waiting', '${stats['requests_waiting']}', '${stats['invites_open']} invites unused'),
      ('Sources working', '$ok', 'of ${sources.length} checked'),
      ('Titles with backups', '${alt['linked']}', '${alt['waiting']} still to look at'),
    ];
    return _Section(
      label: 'AT A GLANCE',
      child: LayoutBuilder(builder: (context, box) {
        final columns = box.maxWidth >= 560 ? 4 : 2;
        final w = (box.maxWidth - 12 * (columns - 1)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (label, value, sub) in tiles)
              SizedBox(
                width: w,
                child: _Card(
                  child: Semantics(
                    label: '$label: $value, $sub',
                    excludeSemantics: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: AppText.body(size: 12.5, color: AppColors.text60)),
                        const SizedBox(height: 6),
                        Text(value, style: AppText.heading(size: 26)),
                        const SizedBox(height: 2),
                        Text(sub, style: AppText.mono(size: 11, color: AppColors.text45)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _SourceHealth extends StatelessWidget {
  final List<Map<String, dynamic>> sources;
  final VoidCallback onCheck;
  const _SourceHealth({required this.sources, required this.onCheck});

  Widget _row(Map<String, dynamic> s) {
    final st = sourceStatus(s['status'] as String);
    final error = (s['error'] as String?)?.split('\n').first.replaceFirst('Exception while fetching data ', '');
    return ListTile(
      minVerticalPadding: 10,
      leading: Icon(st.icon, color: st.color, semanticLabel: st.label),
      title: Text(_shortName(s['name'] as String), style: AppText.body(size: 14.5, weight: FontWeight.w600)),
      subtitle: Text(
        [
          '${st.label} · ${s['latency']} s · ${agoText(s['checked_at'] as num?)}',
          if (error != null && error.isNotEmpty) error,
        ].join('\n'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: AppText.body(size: 12.5, color: AppColors.text60),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _Section(
        label: 'SOURCE HEALTH',
        action: TextButton.icon(
          onPressed: onCheck,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Check now'),
        ),
        child: _Card(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: sources.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('No checks yet - they run every night at 03:00.',
                      style: AppText.body(size: 13.5, color: AppColors.text60)),
                )
              : Column(children: [for (final s in sources) _row(s)]),
        ),
      );
}

class _SourceOrder extends StatelessWidget {
  final List<String> order;
  final Map<String, String> names;
  final void Function(int from, int to) onReorder;
  const _SourceOrder({required this.order, required this.names, required this.onReorder});

  @override
  Widget build(BuildContext context) => _Section(
        label: 'WHERE TO LOOK FOR BACKUPS FIRST',
        child: _Card(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: onReorder,
            children: [
              for (final (i, id) in order.indexed)
                ListTile(
                  key: ValueKey(id),
                  leading: Text('${i + 1}', style: AppText.mono(size: 13, color: AppColors.text45)),
                  title: Text(_shortName(names[id] ?? 'Source $id'), style: AppText.body(size: 14.5)),
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.drag_handle, semanticLabel: 'Drag to reorder'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}

class _Alternates extends StatelessWidget {
  final Map<String, dynamic> counts;
  final VoidCallback onRun;
  const _Alternates({required this.counts, required this.onRun});

  @override
  Widget build(BuildContext context) {
    final total = (counts['total'] as num?)?.toInt() ?? 0;
    final waiting = (counts['waiting'] as num?)?.toInt() ?? 0;
    final done = total - waiting;
    return _Section(
      label: 'BACKUP SOURCES',
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${counts['linked']} titles have backups (${counts['alternates']} copies in all). '
              "When a chapter won't load, the reader uses the next copy.",
              style: AppText.body(size: 13.5, color: AppColors.text60),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              semanticsLabel: 'Titles looked at',
            ),
            const SizedBox(height: 6),
            Text('$done of $total looked at', style: AppText.mono(size: 11, color: AppColors.text45)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onRun, child: const Text('Look again for the whole library')),
            ),
          ],
        ),
      ),
    );
  }
}

class _People extends StatelessWidget {
  final List<Map<String, dynamic>> people;
  const _People({required this.people});

  @override
  Widget build(BuildContext context) => _Section(
        label: 'PEOPLE',
        child: _Card(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            for (final p in people)
              ListTile(
                minVerticalPadding: 10,
                title: Text('${p['username']}', style: AppText.body(size: 14.5, weight: FontWeight.w600)),
                subtitle: Text(
                  '${p['role'] == 'owner' ? 'You' : 'Friend'} · seen ${agoText(p['last_seen'] as num?)}'
                  ' · ${p['manga_library']} manga · ${p['history']} read',
                  style: AppText.body(size: 12.5, color: AppColors.text60),
                ),
              ),
          ]),
        ),
      );
}
