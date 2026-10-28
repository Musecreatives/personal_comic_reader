import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../backends/suwayomi/suwayomi_backend.dart';
import '../../core/backend/models.dart';
import '../shared/series_cover.dart';

typedef _Hits = ({String source, List<({int id, String title, String thumbnailUrl})> hits});

/// Finds [series] on the other installed extensions and moves it to the one
/// picked (read chapters and categories come along). Returns the new id, or
/// null when nothing was migrated. With [link], the pick is added as a
/// backup source instead (plan item 1) and nothing moves.
Future<int?> showMigrateSheet(
    BuildContext context, SuwayomiBackend backend, Series series,
    {bool link = false}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.card,
    constraints: const BoxConstraints(maxWidth: 720),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) =>
          _MigrateSheet(backend: backend, series: series, scroll: scroll, link: link),
    ),
  );
}

class _MigrateSheet extends StatefulWidget {
  final SuwayomiBackend backend;
  final Series series;
  final ScrollController scroll;
  final bool link;
  const _MigrateSheet(
      {required this.backend,
      required this.series,
      required this.scroll,
      this.link = false});

  @override
  State<_MigrateSheet> createState() => _MigrateSheetState();
}

class _MigrateSheetState extends State<_MigrateSheet> {
  late final _query = TextEditingController(text: widget.series.title);
  final _results = <_Hits>[];
  var _pending = 0;
  var _generation = 0;
  var _migrating = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final gen = ++_generation;
    final q = _query.text.trim();
    setState(() {
      _results.clear();
      _pending = 0;
    });
    if (q.isEmpty) return;
    final hidden = ProviderScope.containerOf(context, listen: false)
        .read(hiddenSourcesStoreProvider);
    final current =
        await widget.backend.sourceIdOf(widget.series.id).catchError((_) => '');
    final sources = hidden
        .visible(await widget.backend.listInstalledSources())
        .where((s) =>
            s.id != current && s.id != '0' && (s.lang == 'en' || s.lang == 'all'))
        .toList();
    if (!mounted || gen != _generation) return;
    setState(() => _pending = sources.length);
    // A few sources at a time: each search hits a different website.
    for (var i = 0; i < sources.length; i += 6) {
      await Future.wait(sources.skip(i).take(6).map((s) async {
        try {
          final page = await widget.backend.browseSource(s.id, query: q);
          if (mounted && gen == _generation && page.mangas.isNotEmpty) {
            setState(() =>
                _results.add((source: s.name, hits: page.mangas.take(8).toList())));
          }
        } catch (_) {
          // An extension that's down just shows no results.
        } finally {
          if (mounted && gen == _generation) setState(() => _pending--);
        }
      }));
      if (!mounted || gen != _generation) return;
    }
  }

  Future<void> _pick(String source, ({int id, String title, String thumbnailUrl}) m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(widget.link ? 'Add as a backup?' : 'Migrate?'),
        content: Text(widget.link
            ? '"${m.title}" on $source becomes a backup for "${widget.series.title}". '
                'When the main source can\'t load a chapter, it\'s read from here. '
                'It isn\'t added to your library.'
            : '"${widget.series.title}" moves to "${m.title}" on $source. Chapters '
                'you\'ve read stay read and its categories come along; the old copy '
                'leaves your library.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(d, true),
              child: Text(widget.link ? 'Add backup' : 'Migrate')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _migrating = true);
    try {
      if (widget.link) {
        await widget.backend.linkSource(widget.series.id, m.id);
      } else {
        await widget.backend.migrate(widget.series.id, m.id);
      }
      if (mounted) Navigator.pop(context, m.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _migrating = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(
              content: Text(widget.link ? "Couldn't add the backup: $e" : "Couldn't migrate: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView(
          controller: widget.scroll,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            Text(widget.link ? 'Add a backup source' : 'Migrate to another extension',
                style: AppText.body(size: 17, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              widget.series.sourceName == null
                  ? 'Pick the same title on another source.'
                  : 'Now on ${widget.series.sourceName}. Pick the same title on another source.',
              style: AppText.body(size: 12.5, color: AppColors.text60),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _query,
              style: AppText.body(size: 14),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: AppColors.fillSubtle,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),
            if (_pending > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('Searching $_pending more sources…',
                    style: AppText.mono(size: 10, color: AppColors.text45)),
              ),
            if (_pending == 0 && _results.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('No other source has a match. Try a shorter title.',
                    textAlign: TextAlign.center,
                    style: AppText.body(color: AppColors.text45)),
              ),
            for (final r in _results) ...[
              Text(r.source.toUpperCase(), style: AppText.sectionLabel()),
              const SizedBox(height: 8),
              SizedBox(
                height: 190,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: r.hits.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final m = r.hits[i];
                    return SizedBox(
                      width: 100,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: _migrating ? null : () => _pick(r.source, m),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.zero,
                                child: SizedBox.expand(
                                  child: SeriesCover(
                                    imageUrl: m.thumbnailUrl,
                                    headers: widget.backend.imageHeaders,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(m.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.body(size: 11.5)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
            ],
          ],
        ),
        if (_migrating)
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.card.withValues(alpha: 0.8),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 14),
                    Text(widget.link ? 'Adding…' : 'Migrating…', style: AppText.body(color: AppColors.text60)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
