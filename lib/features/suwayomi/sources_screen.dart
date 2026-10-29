import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/brand_seal.dart';
import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../backends/suwayomi/suwayomi_maintenance_client.dart';
import '../discovery/discovery_providers.dart';
import '../shared/app_sheet.dart';
import '../shared/back_button.dart';
import '../shared/error_state.dart';
import '../shared/ink_chip.dart';

/// A client for the Suwayomi server, or null when none is configured.
/// Found among all servers, so it works whichever one is active.
final suwayomiAdminProvider =
    FutureProvider<SuwayomiMaintenanceClient?>((ref) async {
  final backend = await ref.watch(suwayomiBackendProvider.future);
  if (backend == null) return null;
  return SuwayomiMaintenanceClient(
      config: backend.config, headers: backend.imageHeaders);
});

/// Sources listed first, in this order: the ones this library leans on.
const pinnedSourceIds = [
  '4215511432986138970', // Mangabat
  '7185601298150078890', // Read Comics Online
];

/// Where Suwayomi finds manga and comics. Everyone sees the installed
/// sources and can open one; the owner also manages extensions and repos.
class SourcesScreen extends ConsumerStatefulWidget {
  const SourcesScreen({super.key});

  @override
  ConsumerState<SourcesScreen> createState() => _SourcesScreenState();
}

enum _Tab { sources, extensions, repos }

class _SourcesScreenState extends ConsumerState<SourcesScreen> {
  var _tab = _Tab.sources;

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(isOwnerProvider);
    final tab = owner ? _tab : _Tab.sources;
    final client = ref.watch(suwayomiAdminProvider);

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        // Header and content share one column, capped like Settings, so on
        // a tablet the title sits over its list instead of at the far edge.
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: Row(
                children: [
                  const AppBackButton(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(owner ? 'Sources & extensions' : 'Sources',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.largeTitle(size: 22)),
                  ),
                ],
              ),
            ),
            if (owner)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: PillTabs<_Tab>(
                  value: tab,
                  options: const {
                    _Tab.sources: 'SOURCES',
                    _Tab.extensions: 'EXTENSIONS',
                    _Tab.repos: 'REPOS',
                  },
                  onChanged: (t) => setState(() => _tab = t),
                ),
              ),
            Expanded(
              child: client.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => AppErrorState(
                    error: e, onRetry: () => ref.invalidate(suwayomiAdminProvider)),
                data: (c) {
                  if (c == null) {
                    return const EmptyState(
                      title: 'No Suwayomi server',
                      message:
                          'Sources come from a Suwayomi server. Add one in Settings, Sources & servers.',
                    );
                  }
                  return switch (tab) {
                    _Tab.sources => _SourcesTab(client: c),
                    _Tab.extensions => _ExtensionsTab(client: c),
                    _Tab.repos => _ReposTab(client: c),
                  };
                },
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

// ---------------------------------------------------------------------------
// Sources

class _SourcesTab extends ConsumerStatefulWidget {
  final SuwayomiMaintenanceClient client;
  const _SourcesTab({required this.client});

  @override
  ConsumerState<_SourcesTab> createState() => _SourcesTabState();
}

class _SourcesTabState extends ConsumerState<_SourcesTab> {
  late Future<List<SourceSummary>> _future = widget.client.sources();
  var _showOther = false;

  Future<void> _reload() async {
    setState(() => _future = widget.client.sources());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(hiddenSourcesRevisionProvider);
    final hidden = ref.read(hiddenSourcesStoreProvider);
    return FutureBuilder<List<SourceSummary>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return AppErrorState(error: snap.error!, onRetry: _reload);
        final all = snap.data;
        if (all == null) return const Center(child: CircularProgressIndicator());
        if (all.isEmpty) {
          return const EmptyState(
            title: 'No sources yet',
            message: 'Install an extension and its sources show up here.',
          );
        }

        final pinned = [
          for (final id in pinnedSourceIds) ...all.where((s) => s.id == id),
        ];
        bool main(SourceSummary s) => s.lang == 'en' || s.lang == 'all';
        int byName(SourceSummary a, SourceSummary b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase());
        final rest = all.where((s) => !pinnedSourceIds.contains(s.id));
        final english = rest.where(main).toList()..sort(byName);
        final other = rest.where((s) => !main(s)).toList()
          ..sort((a, b) => a.lang == b.lang ? byName(a, b) : a.lang.compareTo(b.lang));

        Widget row(SourceSummary s) => _SourceRow(
              source: s,
              headers: widget.client.imageHeaders,
              hidden: hidden.isHidden(s.id),
              onTap: () => context.push('/settings/sources/${s.id}'),
            );

        return RefreshIndicator.adaptive(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              if (pinned.isNotEmpty) ...[
                const SectionLabel('PINNED'),
                HairlinePanel(children: [for (final s in pinned) row(s)]),
              ],
              if (english.isNotEmpty) ...[
                const SectionLabel('ENGLISH AND MULTI-LANGUAGE'),
                HairlinePanel(children: [for (final s in english) row(s)]),
              ],
              if (other.isNotEmpty) ...[
                const SectionLabel('OTHER LANGUAGES'),
                HairlinePanel(children: [
                  if (_showOther || other.length <= 3) for (final s in other) row(s),
                  if (other.length > 3)
                  _PlainRow(
                    title: _showOther
                        ? 'Hide other languages'
                        : 'Show ${other.length} more in other languages',
                    onTap: () => setState(() => _showOther = !_showOther),
                  ),
                ]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SourceRow extends StatelessWidget {
  final SourceSummary source;
  final Map<String, String> headers;
  final bool hidden;
  final VoidCallback onTap;
  const _SourceRow({
    required this.source,
    required this.headers,
    required this.hidden,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _Tappable(
      onTap: onTap,
      child: Row(
        children: [
          SourceIcon(url: source.iconUrl, name: source.name, headers: headers),
          const SizedBox(width: 12),
          Expanded(
            child: Text(source.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(
                    size: 15,
                    weight: FontWeight.w500,
                    color: hidden ? AppColors.text45 : AppColors.text)),
          ),
          if (source.rating == ContentRating.adult) ...[
            Text('18+', style: AppText.mono(size: 10.5)),
            const SizedBox(width: 10),
          ],
          if (hidden) ...[
            Text('HIDDEN', style: AppText.mono(size: 10.5)),
            const SizedBox(width: 10),
          ],
          Text(langLabel(source.lang), style: AppText.mono(size: 10.5)),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, size: 18, color: AppColors.text45),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Extensions (owner)

class _ExtensionsTab extends StatefulWidget {
  final SuwayomiMaintenanceClient client;
  const _ExtensionsTab({required this.client});

  @override
  State<_ExtensionsTab> createState() => _ExtensionsTabState();
}

class _ExtensionsTabState extends State<_ExtensionsTab> {
  static const _maxResults = 60;
  late Future<List<ExtensionInfo>> _future = widget.client.extensions();
  final _search = TextEditingController();
  var _query = '';
  var _allLanguages = false;
  final _busy = <String>{};
  var _updatingAll = false;
  _Notice? _notice;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() => _future = widget.client.extensions());
    await _future;
  }

  /// Runs [action] for [pkg], showing a spinner on its row and a notice
  /// with the outcome, then reloads the catalog.
  Future<void> _run(String pkg, Future<void> Function() action, String done) async {
    setState(() {
      _busy.add(pkg);
      _notice = null;
    });
    try {
      await action();
      _notice = _Notice(done);
      await _reload();
    } on StaleExtensionFileException catch (e) {
      _notice = _Notice('$e', error: true);
    } catch (e) {
      _notice = _Notice.failed(e);
    } finally {
      if (mounted) setState(() => _busy.remove(pkg));
    }
  }

  Future<void> _updateAll(List<ExtensionInfo> updates) async {
    setState(() {
      _updatingAll = true;
      _notice = null;
    });
    try {
      await widget.client.updateExtensions([for (final e in updates) e.pkgName]);
      _notice = _Notice(updates.length == 1
          ? 'Updated ${updates.single.name}.'
          : 'Updated ${updates.length} extensions.');
      await _reload();
    } catch (e) {
      _notice = _Notice.failed(e);
    } finally {
      if (mounted) setState(() => _updatingAll = false);
    }
  }

  Future<void> _openActions(ExtensionInfo ext) async {
    final action = await showAppSheet<String>(
      context: context,
      grabber: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
              child: Text(ext.name, style: AppText.heading(size: 18)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(_extMeta(ext), style: AppText.mono(size: 10.5)),
            ),
            if (ext.sourceIds.isNotEmpty)
              _SheetAction(
                icon: Icons.info_outline,
                label: ext.sourceIds.length == 1
                    ? 'Source details'
                    : 'Source details (${ext.sourceIds.length} languages)',
                onTap: () => Navigator.pop(sheet, 'details'),
              ),
            if (ext.hasUpdate)
              _SheetAction(
                icon: Icons.system_update_alt,
                label: 'Update',
                onTap: () => Navigator.pop(sheet, 'update'),
              ),
            _SheetAction(
              icon: Icons.delete_outline,
              label: 'Uninstall',
              danger: true,
              onTap: () => Navigator.pop(sheet, 'uninstall'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'details':
        // A multi-language extension opens its first source.
        await context.push('/settings/sources/${ext.sourceIds.first}');
      case 'update':
        await _run(ext.pkgName, () => widget.client.updateExtension(ext.pkgName),
            'Updated ${ext.name}.');
      case 'uninstall':
        final ok = await confirmDanger(
          context,
          title: 'Uninstall ${ext.name}?',
          body: 'Its sources disappear from search and browse. Series already in '
              'your library stay, but stop getting new chapters until you install it again.',
          action: 'Uninstall',
        );
        if (ok) {
          await _run(ext.pkgName, () => widget.client.uninstallExtension(ext.pkgName),
              'Uninstalled ${ext.name}.');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ExtensionInfo>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return AppErrorState(error: snap.error!, onRetry: _reload);
        final all = snap.data;
        if (all == null) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text('Asking the repos what they have',
                  style: AppText.body(size: 13, color: AppColors.text60)),
            ]),
          );
        }

        final q = _query.toLowerCase();
        bool matches(ExtensionInfo e) =>
            (_allLanguages || e.lang == 'en' || e.lang == 'all') &&
            (q.isEmpty ||
                e.name.toLowerCase().contains(q) ||
                e.pkgName.toLowerCase().contains(q));
        final installed = all.where((e) => e.isInstalled).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        final updates = installed.where((e) => e.hasUpdate).toList();
        final shownInstalled = installed.where(matches).toList();
        final available = all.where((e) => !e.isInstalled).toList();
        final matching =
            q.isEmpty ? const <ExtensionInfo>[] : available.where(matches).toList();
        final found = matching.take(_maxResults).toList();

        return RefreshIndicator.adaptive(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              if (_notice != null) ...[
                NoticeBox(
                    text: _notice!.text, detail: _notice!.detail, error: _notice!.error),
                const SizedBox(height: 14),
              ],
              if (updates.isNotEmpty) ...[
                _UpdatesBlock(
                  updates: updates,
                  busy: _updatingAll,
                  onUpdateAll: () => _updateAll(updates),
                ),
                const SizedBox(height: 18),
              ],
              Row(
                children: [
                  Expanded(
                    child: SearchBox(
                      controller: _search,
                      hint: 'Search ${all.length} extensions',
                      onChanged: (v) => setState(() => _query = v.trim()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  PillTabs<bool>(
                    value: _allLanguages,
                    options: const {false: 'EN', true: 'ALL'},
                    onChanged: (v) => setState(() => _allLanguages = v),
                  ),
                ],
              ),
              SectionLabel('INSTALLED  ${shownInstalled.length}'),
              if (shownInstalled.isEmpty)
                _Hint(q.isEmpty ? 'Nothing installed.' : 'No installed extension matches.')
              else
                HairlinePanel(children: [
                  for (final e in shownInstalled)
                    _ExtensionRow(
                      ext: e,
                      headers: widget.client.imageHeaders,
                      busy: _busy.contains(e.pkgName) || (_updatingAll && e.hasUpdate),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (e.hasUpdate)
                          _TextAction(
                              'Update',
                              () => _run(e.pkgName,
                                  () => widget.client.updateExtension(e.pkgName),
                                  'Updated ${e.name}.')),
                        IconButton(
                          tooltip: 'More for ${e.name}',
                          icon: Icon(Icons.more_horiz, color: AppColors.text60),
                          onPressed: () => _openActions(e),
                        ),
                      ]),
                      onTap: () => _openActions(e),
                    ),
                ]),
              SectionLabel(q.isEmpty
                  ? 'AVAILABLE  ${available.length}'
                  : 'AVAILABLE  ${matching.length} MATCHING'),
              if (q.isEmpty)
                const _Hint('Search above to find an extension to install.')
              else if (found.isEmpty)
                _Hint(_allLanguages
                    ? 'No extension matches "$_query".'
                    : 'No English extension matches "$_query". Try ALL for other languages.')
              else
                HairlinePanel(children: [
                  for (final e in found)
                    _ExtensionRow(
                      ext: e,
                      headers: widget.client.imageHeaders,
                      busy: _busy.contains(e.pkgName),
                      trailing: _TextAction(
                          'Install',
                          () => _run(e.pkgName,
                              () => widget.client.installExtension(e.pkgName),
                              'Installed ${e.name}.')),
                    ),
                ]),
              if (matching.length > found.length)
                _Hint('Showing ${found.length} of ${matching.length}. '
                    'Type more to narrow it down.'),
            ],
          ),
        );
      },
    );
  }
}

String _extMeta(ExtensionInfo e) => [
      langLabel(e.lang),
      'V${e.versionName}',
      if (e.repoName != null) e.repoName!.toUpperCase(),
    ].join('  ');

class _UpdatesBlock extends StatelessWidget {
  final List<ExtensionInfo> updates;
  final bool busy;
  final VoidCallback onUpdateAll;
  const _UpdatesBlock(
      {required this.updates, required this.busy, required this.onUpdateAll});

  @override
  Widget build(BuildContext context) {
    final n = updates.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.text, width: 2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n == 1 ? '1 update ready' : '$n updates ready',
                    style: AppText.body(size: 15, weight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(updates.map((e) => e.name).join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(size: 12.5, color: AppColors.text60)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          busy
              ? const SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : InkButton(
                  label: 'Update all', filled: true, height: 42, onTap: onUpdateAll),
        ],
      ),
    );
  }
}

class _ExtensionRow extends StatelessWidget {
  final ExtensionInfo ext;
  final Map<String, String> headers;
  final bool busy;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _ExtensionRow({
    required this.ext,
    required this.headers,
    required this.busy,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _Tappable(
      onTap: onTap,
      child: Row(
        children: [
          SourceIcon(url: ext.iconUrl, name: ext.name, headers: headers),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ext.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(size: 15, weight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(_extMeta(ext), style: AppText.mono(size: 10)),
                if (ext.isObsolete) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 13, color: AppColors.warningText),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text('No repo offers this any more',
                          style: AppText.body(size: 12, color: AppColors.warningText)),
                    ),
                  ]),
                ],
              ],
            ),
          ),
          if (busy)
            const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else if (trailing != null)
            trailing!
          else if (onTap != null)
            Icon(Icons.chevron_right, size: 18, color: AppColors.text45),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Repos (owner)

class _ReposTab extends StatefulWidget {
  final SuwayomiMaintenanceClient client;
  const _ReposTab({required this.client});

  @override
  State<_ReposTab> createState() => _ReposTabState();
}

class _ReposTabState extends State<_ReposTab> {
  late Future<List<ExtensionRepo>> _future = widget.client.extensionRepos();
  _Notice? _notice;

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() => _future = widget.client.extensionRepos());
    await _future;
  }

  Future<void> _remove(ExtensionRepo repo, int count) async {
    final ok = await confirmDanger(
      context,
      title: 'Remove ${repo.name}?',
      body: count == 1
          ? 'It is the only repo: nothing new can be installed or updated until you add one. Installed extensions stay.'
          : 'Extensions installed from it stay, but stop getting updates.',
      action: 'Remove',
    );
    if (!ok) return;
    try {
      await widget.client.removeExtensionRepo(repo.indexUrl);
      _notice = _Notice('Removed ${repo.name}.');
    } catch (e) {
      _notice = _Notice.failed(e);
    }
    await _reload();
  }

  Future<void> _add() async {
    final name = await showAppSheet<String>(
      context: context,
      grabber: true,
      isScrollControlled: true,
      builder: (_) => _AddRepoSheet(client: widget.client),
    );
    if (name == null || !mounted) return;
    _notice = _Notice(name.isEmpty ? 'Added the repo.' : 'Added $name.');
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ExtensionRepo>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return AppErrorState(error: snap.error!, onRetry: _reload);
        final repos = snap.data;
        if (repos == null) return const Center(child: CircularProgressIndicator());
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            if (_notice != null) ...[
              NoticeBox(
                  text: _notice!.text, detail: _notice!.detail, error: _notice!.error),
              const SizedBox(height: 14),
            ],
            Text(
              'A repo is a list of extensions. Suwayomi checks each one for new '
              'extensions and updates.',
              style: AppText.body(size: 13, color: AppColors.text60),
            ),
            const SizedBox(height: 14),
            if (repos.isEmpty)
              const _Hint('No repos. Add one to install extensions.')
            else
              HairlinePanel(children: [
                for (final r in repos)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.name.isEmpty ? 'Unnamed repo' : r.name,
                                  style: AppText.body(size: 15, weight: FontWeight.w500)),
                              const SizedBox(height: 3),
                              Text(r.indexUrl,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.mono(size: 10.5, color: AppColors.text60)),
                              if (r.signingKey != null && r.signingKey!.length >= 8) ...[
                                const SizedBox(height: 2),
                                Text('KEY ${r.signingKey!.substring(0, 8)}',
                                    style: AppText.mono(size: 10)),
                              ],
                            ],
                          ),
                        ),
                        _TextAction('Remove', () => _remove(r, repos.length), danger: true),
                      ],
                    ),
                  ),
              ]),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: InkButton(
                  icon: Icons.add, label: 'Add repo', filled: true, onTap: _add),
            ),
          ],
        );
      },
    );
  }
}

class _AddRepoSheet extends StatefulWidget {
  final SuwayomiMaintenanceClient client;
  const _AddRepoSheet({required this.client});

  @override
  State<_AddRepoSheet> createState() => _AddRepoSheetState();
}

class _AddRepoSheetState extends State<_AddRepoSheet> {
  final _url = TextEditingController();
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final name = await widget.client.addExtensionRepo(_url.text);
      if (mounted) Navigator.pop(context, name);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error =
          "Suwayomi couldn't read a repo at that address. Check it opens in a browser.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add a repo', style: AppText.heading(size: 18)),
          const SizedBox(height: 16),
          Text('Index address',
              style: AppText.body(size: 13, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _url,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enabled: !_busy,
            onSubmitted: (_) => _submit(),
            style: AppText.mono(size: 13, color: AppColors.text),
            decoration: InputDecoration(
              hintText: 'https://example.org/index.min.json',
              hintStyle: AppText.mono(size: 13, color: AppColors.text45),
              errorText: _error,
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 6),
          Text("The repo's index file. It starts with https://",
              style: AppText.body(size: 12, color: AppColors.text60)),
          const SizedBox(height: 16),
          const NoticeBox(
            text: 'Extensions run on your server with access to your library. '
                'Add only repos you trust.',
            warning: true,
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: Text('Cancel',
                    style: AppText.body(size: 14, color: AppColors.text60)),
              ),
              const SizedBox(width: 8),
              _busy
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : InkButton(label: 'Add', filled: true, height: 44, onTap: _submit),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared pieces (also used by the source details page)

class _Notice {
  final String text;
  final String? detail;
  final bool error;
  const _Notice(this.text, {this.error = false}) : detail = null;

  /// A failure: a plain headline, with the server's own words kept below.
  _Notice.failed(Object e)
      : text = '${AppErrorState.errorHeadline(e)}. Nothing changed; try again.',
        detail = '$e',
        error = true;
}

/// A language code as rows show it; Suwayomi's "all" is one multi-language
/// source, not the EN/ALL filter.
String langLabel(String lang) => lang == 'all' ? 'MULTI' : lang.toUpperCase();

/// An outcome or warning in a box. Errors get the danger edge, icon and
/// colour (the design system "Errors"); warnings amber; a plain notice is quiet.
class NoticeBox extends StatelessWidget {
  final String text;

  /// The raw cause, shown small under [text]; the headline stays readable.
  final String? detail;
  final bool error;
  final bool warning;
  const NoticeBox(
      {super.key,
      required this.text,
      this.detail,
      this.error = false,
      this.warning = false});

  @override
  Widget build(BuildContext context) {
    final flagged = error || warning;
    final color = error ? AppColors.dangerText : AppColors.warningText;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.fillSubtle,
        borderRadius: BorderRadius.circular(12),
        border: flagged ? Border.all(color: color, width: 2) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (flagged) ...[
            Icon(error ? Icons.error_outline : Icons.warning_amber_rounded,
                size: 18, color: color),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text,
                    style: AppText.body(
                        size: 12.5,
                        color: flagged ? AppColors.text : AppColors.text60)),
                if (detail != null) ...[
                  const SizedBox(height: 4),
                  Text(detail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.mono(size: 10.5)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A source or extension icon from Suwayomi, square like covers, with the
/// name's first letter while it loads or when there is none.
class SourceIcon extends StatelessWidget {
  final String? url;
  final String name;
  final Map<String, String> headers;
  final double size;
  const SourceIcon({
    super.key,
    required this.url,
    required this.name,
    required this.headers,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    final letter = Container(
      color: AppColors.fillSubtle,
      alignment: Alignment.center,
      child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
          style: AppText.mono(size: size * 0.4, color: AppColors.text60)),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(border: Border.all(color: AppColors.border)),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? letter
          : CachedNetworkImage(
              imageUrl: url!,
              httpHeaders: headers,
              fit: BoxFit.cover,
              placeholder: (_, _) => letter,
              errorWidget: (_, _, _) => letter,
            ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String label;
  const SectionLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 22, 0, 8),
        child: Text(label, style: AppText.sectionLabel()),
      );
}

/// Rows in one card, separated by hairlines (as on the Settings screen).
class HairlinePanel extends StatelessWidget {
  final List<Widget> children;
  const HairlinePanel({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: AppColors.border)),
              ),
              child: children[i],
            ),
        ],
      ),
    );
  }
}

/// Mono pill tabs. The selected one is ink, not violet, so the screen's one
/// violet action stays the only one; each segment is a 40px focusable target.
class PillTabs<T> extends StatelessWidget {
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  const PillTabs(
      {super.key, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.fillSubtle,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final MapEntry(key: v, value: label) in options.entries)
            Semantics(
              button: true,
              selected: v == value,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => onChanged(v),
                  borderRadius: BorderRadius.circular(999),
                  child: AnimatedContainer(
                    duration: Motion.scaled(context, Motion.fast),
                    curve: Motion.easeOut,
                    constraints: const BoxConstraints(minHeight: 40),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: v == value ? AppColors.text : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(label,
                        style: AppText.mono(
                            size: 10.5,
                            color: v == value ? AppColors.page : AppColors.text60)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  const SearchBox(
      {super.key, required this.controller, required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.fillSubtle,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: AppColors.text45),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: AppText.body(size: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: AppText.body(size: 14, color: AppColors.text45),
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, v, _) => v.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Clear search',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close, size: 16, color: AppColors.text60),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Asks before something destructive; true when confirmed.
Future<bool> confirmDanger(BuildContext context,
    {required String title, required String body, required String action}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(d, true),
          child: Text(action, style: TextStyle(color: AppColors.dangerText)),
        ),
      ],
    ),
  );
  return ok == true;
}

class _Tappable extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  const _Tappable({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _PlainRow extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  const _PlainRow({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) => _Tappable(
        onTap: onTap,
        child: Row(children: [
          Expanded(
              child: Text(title,
                  style: AppText.body(size: 14, weight: FontWeight.w600))),
          Icon(Icons.expand_more, size: 18, color: AppColors.text45),
        ]),
      );
}

/// A row's inline action. Ink, not violet: the screen keeps violet for its
/// one primary action (the design system "The One Violet Rule"). Danger always comes
/// with an icon.
class _TextAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const _TextAction(this.label, this.onTap, {this.danger = false});

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.dangerText : AppColors.text;
    final text = Text(label,
        style: AppText.body(size: 13, weight: FontWeight.w600, color: color));
    return danger
        ? TextButton.icon(
            onPressed: onTap,
            icon: Icon(Icons.delete_outline, size: 16, color: color),
            label: text)
        : TextButton(onPressed: onTap, child: text);
  }
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback onTap;
  const _SheetAction(
      {required this.icon, required this.label, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.dangerText : AppColors.text;
    return _Tappable(
      onTap: onTap,
      child: Row(children: [
        Icon(icon, size: 21, color: color),
        const SizedBox(width: 16),
        Text(label,
            style: AppText.body(size: 15, weight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, style: AppText.body(size: 13, color: AppColors.text45)),
      );
}
