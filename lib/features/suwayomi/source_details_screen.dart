import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../backends/suwayomi/suwayomi_maintenance_client.dart';
import '../shared/app_sheet.dart';
import '../shared/back_button.dart';
import '../shared/error_state.dart';
import '../shared/ink_chip.dart';
import 'sources_screen.dart';

/// One source: browse it, whether this account sees it in search, what it
/// is, and (owner) whether it works right now and its own settings. Only the
/// owner changes settings: they change how the server reads the site for
/// everyone.
class SourceDetailsScreen extends ConsumerStatefulWidget {
  final String sourceId;
  const SourceDetailsScreen({super.key, required this.sourceId});

  @override
  ConsumerState<SourceDetailsScreen> createState() => _SourceDetailsScreenState();
}

class _SourceDetailsScreenState extends ConsumerState<SourceDetailsScreen> {
  SuwayomiMaintenanceClient? _client;
  SourceDetails? _details;
  Object? _error;
  SourceCheck? _check;
  var _checking = false;

  /// Loads (or reloads) the details. The page keeps showing the last ones
  /// meanwhile, so saving a setting doesn't blank it or lose the scroll.
  Future<void> _load() async {
    try {
      final d = await _client!.sourceDetails(widget.sourceId);
      if (mounted) {
        setState(() {
          _details = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _runCheck() async {
    setState(() {
      _checking = true;
      _check = null;
    });
    try {
      final result = await _client!.checkSource(widget.sourceId);
      if (mounted) setState(() => _check = result);
    } catch (e) {
      if (mounted) {
        setState(() => _check = SourceCheck([
              SourceCheckStep(name: 'Catalog', took: Duration.zero, error: '$e'),
            ]));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _set(SourcePreference pref, Object value) async {
    try {
      await _client!.setSourcePreference(widget.sourceId, pref, value);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "${AppErrorState.errorHeadline(e)}. The setting wasn't saved.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientAsync = ref.watch(suwayomiAdminProvider);
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        // Header and content share one column, capped like Settings.
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 6, 20, 4),
                  child: AppBackButton(),
                ),
                Expanded(
                  child: clientAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => AppErrorState(
                        error: e,
                        onRetry: () => ref.invalidate(suwayomiAdminProvider)),
                    data: (client) {
                      if (client == null) {
                        return Center(
                          child: Text('No Suwayomi server.',
                              style: AppText.body(color: AppColors.text45)),
                        );
                      }
                      if (_client != client) {
                        _client = client;
                        _load();
                      }
                      final s = _details;
                      if (s == null && _error != null) {
                        return AppErrorState(error: _error!, onRetry: _load);
                      }
                      if (s == null) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return _Body(
                        source: s,
                        client: client,
                        check: _check,
                        checking: _checking,
                        onCheck: _runCheck,
                        onSet: _set,
                      );
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

class _Body extends ConsumerWidget {
  final SourceDetails source;
  final SuwayomiMaintenanceClient client;
  final SourceCheck? check;
  final bool checking;
  final VoidCallback onCheck;
  final void Function(SourcePreference pref, Object value) onSet;
  const _Body({
    required this.source,
    required this.client,
    required this.check,
    required this.checking,
    required this.onCheck,
    required this.onSet,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(hiddenSourcesRevisionProvider);
    final owner = ref.watch(isOwnerProvider);
    final hiddenStore = ref.read(hiddenSourcesStoreProvider);
    final hidden = hiddenStore.isHidden(source.id);
    final prefs = source.preferences.where((p) => p.visible).toList();
    final meta = [
      langLabel(source.lang),
      if (source.versionName != null) 'V${source.versionName}',
      if (source.repoName != null) source.repoName!.toUpperCase(),
    ].join('  ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        Row(
          children: [
            SourceIcon(
                url: source.iconUrl,
                name: source.name,
                headers: client.imageHeaders,
                size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(source.name, style: AppText.largeTitle(size: 24)),
                  const SizedBox(height: 6),
                  Text(meta, style: AppText.mono(size: 10.5)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        // The friend's one primary action. The owner's is the health check,
        // so here Browse is drawn in outline.
        Align(
          alignment: Alignment.centerLeft,
          child: InkButton(
            icon: Icons.travel_explore_outlined,
            label: 'Browse ${source.name}',
            filled: !owner,
            height: 44,
            onTap: () => context.push(
                Uri(path: '/settings/suwayomi/browse', queryParameters: {'source': source.id})
                    .toString()),
          ),
        ),
        if (owner) ...[
          const SectionLabel('HEALTH'),
          _HealthBlock(check: check, checking: checking, onCheck: onCheck),
        ],
        const SectionLabel('FOR YOU'),
        HairlinePanel(children: [
          _SwitchRow(
            title: 'Hide from search and discovery',
            subtitle:
                'Leaves it out of search, browse and recommendations. Only for you; everyone else still sees it.',
            value: hidden,
            onChanged: (v) async {
              await hiddenStore.setHidden(source.id, v);
              ref.read(hiddenSourcesRevisionProvider.notifier).state++;
            },
          ),
        ]),
        const SectionLabel('ABOUT'),
        HairlinePanel(children: [
          if (source.homeUrl != null)
            _InfoRow(
              title: 'Website',
              value: source.homeUrl!,
              mono: true,
              trailingIcon: Icons.copy_outlined,
              onTap: () {
                Clipboard.setData(ClipboardData(text: source.homeUrl!));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Address copied')));
              },
            ),
          _InfoRow(
              title: 'Latest updates',
              value: source.supportsLatest ? 'Listed' : 'Not offered'),
          _InfoRow(
            title: 'Content',
            value: switch (source.rating) {
              ContentRating.safe => 'For all ages',
              ContentRating.mixed => 'Some titles are for adults',
              ContentRating.adult => 'Adult',
            },
          ),
        ]),
        if (prefs.isNotEmpty) ...[
          const SectionLabel('SOURCE SETTINGS'),
          if (!owner)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('Only the server owner can change these.',
                  style: AppText.body(size: 12.5, color: AppColors.text60)),
            ),
          HairlinePanel(children: [
            for (final p in prefs)
              _PreferenceRow(
                pref: p,
                editable: owner && p.enabled,
                onSet: (v) => onSet(p, v),
              ),
          ]),
        ],
      ],
    );
  }
}

class _HealthBlock extends StatelessWidget {
  final SourceCheck? check;
  final bool checking;
  final VoidCallback onCheck;
  const _HealthBlock(
      {required this.check, required this.checking, required this.onCheck});

  /// What a failed step means and what to do, in plain words; the raw cause
  /// stays under it.
  static String _meaning(String step) => switch (step) {
        'Catalog' =>
          "The site didn't return its title list. It may be down or blocking the server; check the website opens.",
        'Chapters' =>
          "The site listed titles but not their chapters. An extension update usually fixes this.",
        'Pages' =>
          "The chapter's page list didn't load. The site may have changed; check for an extension update.",
        _ =>
          "The site's image server refused the page. That is usually on the site's side and passes; meanwhile read the series from another source.",
      };

  @override
  Widget build(BuildContext context) {
    final c = check;
    final failed = c == null || c.ok ? null : c.steps.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (c == null)
          Text(
            "Loads the popular list, a title's chapters and the first image of "
            'its newest chapter, the way the reader does.',
            style: AppText.body(size: 13, color: AppColors.text60),
          )
        else ...[
          Row(children: [
            Icon(c.ok ? Icons.check_circle_outline : Icons.error_outline,
                size: 20, color: c.ok ? AppColors.text : AppColors.dangerText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                c.ok ? 'Working' : 'Failing at ${failed!.name.toLowerCase()}',
                style: AppText.body(
                    size: 15,
                    weight: FontWeight.w700,
                    color: c.ok ? AppColors.text : AppColors.dangerText),
              ),
            ),
          ]),
          if (failed != null) ...[
            const SizedBox(height: 6),
            Text(_meaning(failed.name), style: AppText.body(size: 13)),
          ],
          const SizedBox(height: 10),
          HairlinePanel(children: [
            for (final s in c.steps)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(s.ok ? Icons.check : Icons.close,
                          size: 16,
                          color: s.ok ? AppColors.text : AppColors.dangerText),
                      const SizedBox(width: 10),
                      Expanded(child: Text(s.name, style: AppText.body(size: 14))),
                      Text(_seconds(s.took), style: AppText.mono(size: 10.5)),
                    ]),
                    if (s.error != null) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 26),
                        child: Text(s.error!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.mono(size: 10.5)),
                      ),
                    ],
                  ],
                ),
              ),
          ]),
        ],
        const SizedBox(height: 14),
        checking
            ? Row(children: [
                const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text('Checking', style: AppText.body(size: 13, color: AppColors.text60)),
              ])
            : InkButton(
                icon: Icons.monitor_heart_outlined,
                label: c == null ? 'Check source' : 'Check again',
                filled: c == null,
                height: 44,
                onTap: onCheck,
              ),
      ],
    );
  }

  static String _seconds(Duration d) =>
      '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const _SwitchRow(
      {required this.title, this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      child: Row(
        children: [
          Expanded(child: _TitleBlock(title: title, subtitle: subtitle)),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String title;
  final String value;
  final bool mono;
  final IconData? trailingIcon;
  final VoidCallback? onTap;
  const _InfoRow(
      {required this.title,
      required this.value,
      this.mono = false,
      this.trailingIcon,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Text(title, style: AppText.body(size: 14)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono
                      ? AppText.mono(size: 11, color: AppColors.text60)
                      : AppText.body(size: 14, color: AppColors.text60)),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 8),
              Icon(trailingIcon, size: 16, color: AppColors.text45),
            ],
          ],
        ),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _TitleBlock({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.body(size: 15, weight: FontWeight.w500)),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: AppText.body(size: 12.5, color: AppColors.text60)),
          ],
        ],
      );
}

/// One source setting, drawn for its type. Read-only when not [editable].
class _PreferenceRow extends StatelessWidget {
  final SourcePreference pref;
  final bool editable;
  final ValueChanged<Object> onSet;
  const _PreferenceRow(
      {required this.pref, required this.editable, required this.onSet});

  /// Android preference summaries use `%s` for the current choice. A summary
  /// that only repeats the value shown on the right is dropped.
  String? _summary(String? current) {
    final s = pref.summary;
    if (s == null || s.isEmpty) return null;
    final text = s.replaceAll('%s', current ?? '').trim();
    return text.isEmpty || text == current ? null : text;
  }

  @override
  Widget build(BuildContext context) {
    final title = pref.title ?? pref.key ?? 'Setting';
    final p = pref;
    switch (p) {
      case BoolPreference():
        return _SwitchRow(
          title: title,
          subtitle: _summary(null),
          value: p.value,
          onChanged: editable ? (v) => onSet(v) : null,
        );
      case ListPreference():
        final label = p.selectedLabel ?? 'Not set';
        return _choiceRow(title, _summary(label), label, () async {
          final picked = await _pickOne(context, title, p);
          if (picked != null && picked != p.value) onSet(picked);
        });
      case MultiSelectPreference():
        final n = p.values.length;
        final label = n == 0 ? 'None' : '$n selected';
        return _choiceRow(title, _summary(label), label, () async {
          final picked = await _pickMany(context, title, p);
          if (picked != null) onSet(picked);
        });
      case TextPreference():
        final label = p.value.isEmpty ? 'Not set' : p.value;
        return _choiceRow(title, _summary(label), label, () async {
          final text = await _editText(context, title, p.value);
          if (text != null && text != p.value) onSet(text);
        });
    }
  }

  Widget _choiceRow(
      String title, String? subtitle, String value, VoidCallback onTap) {
    return InkWell(
      onTap: editable ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(child: _TitleBlock(title: title, subtitle: subtitle)),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.mono(size: 11, color: AppColors.text60)),
            ),
            if (editable) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 18, color: AppColors.text45),
            ],
          ],
        ),
      ),
    );
  }

  static String _label(List<String> entries, List<String> values, int i) =>
      i < entries.length ? entries[i] : values[i];

  static Future<String?> _pickOne(
      BuildContext context, String title, ListPreference p) {
    return showAppSheet<String>(
      context: context,
      grabber: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(title, style: AppText.heading(size: 18)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < p.entryValues.length; i++)
                    ListTile(
                      title: Text(_label(p.entries, p.entryValues, i),
                          style: AppText.body(size: 15)),
                      trailing: p.entryValues[i] == p.value
                          ? Icon(Icons.check, color: AppColors.text)
                          : null,
                      onTap: () => Navigator.pop(sheet, p.entryValues[i]),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static Future<Set<String>?> _pickMany(
      BuildContext context, String title, MultiSelectPreference p) {
    final chosen = {...p.values};
    return showAppSheet<Set<String>>(
      context: context,
      grabber: true,
      builder: (sheet) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(title, style: AppText.heading(size: 18)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (var i = 0; i < p.entryValues.length; i++)
                      CheckboxListTile.adaptive(
                        value: chosen.contains(p.entryValues[i]),
                        title: Text(_label(p.entries, p.entryValues, i),
                            style: AppText.body(size: 15)),
                        onChanged: (on) => setState(() => on == true
                            ? chosen.add(p.entryValues[i])
                            : chosen.remove(p.entryValues[i])),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: InkButton(
                      label: 'Save',
                      filled: true,
                      height: 44,
                      onTap: () => Navigator.pop(sheet, chosen)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<String?> _editText(
      BuildContext context, String title, String current) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(title),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(d, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}
