import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../core/backend/models.dart';
import '../../core/metadata/cover_candidates.dart';
import '../shared/app_sheet.dart';
import '../shared/error_state.dart';
import '../shared/ink_chip.dart';
import '../shared/series_cover.dart';

/// Owner only: pick a better cover (and summary, genres, status) for
/// [series] from AniList and MangaDex, or ComicVine for comics, and write
/// it to the server for everyone. [onReset] (Suwayomi) goes back to the
/// source's own cover. Returns true when something was saved.
Future<bool?> showRefreshCoverSheet(
  BuildContext context, {
  required SeriesMetadataEditor editor,
  required Series series,
  required CoverCandidateFinder finder,
  bool comics = false,
  Future<void> Function()? onReset,
}) {
  return showAppSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: Motion.sheetStyle,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (_) => _RefreshCoverSheet(
      editor: editor,
      series: series,
      finder: finder,
      comics: comics,
      onReset: onReset,
    ),
  );
}

class _RefreshCoverSheet extends StatefulWidget {
  final SeriesMetadataEditor editor;
  final Series series;
  final CoverCandidateFinder finder;
  final bool comics;
  final Future<void> Function()? onReset;
  const _RefreshCoverSheet({
    required this.editor,
    required this.series,
    required this.finder,
    required this.comics,
    this.onReset,
  });

  @override
  State<_RefreshCoverSheet> createState() => _RefreshCoverSheetState();
}

class _RefreshCoverSheetState extends State<_RefreshCoverSheet> {
  late final _query = TextEditingController(text: widget.series.title);
  late Future<List<CoverCandidate>> _results = _search();
  CoverCandidate? _picked;
  bool _useCover = true;
  bool _useBanner = true;
  bool _useDetails = true;
  bool _saving = false;

  Future<List<CoverCandidate>> _search() =>
      widget.finder.search(_query.text.trim(), comics: widget.comics);

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool get _bannerOffered =>
      widget.editor.supportsBanner && _picked?.bannerUrl != null;

  bool get _hasDetails {
    final p = _picked;
    return p != null && (p.description != null || p.genres.isNotEmpty || p.status != null);
  }

  Future<void> _save(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      // Komga serves the new cover at the same address, so the cached
      // old one has to go.
      final old = widget.series.thumbnailUrl;
      if (old != null) await CachedNetworkImage.evictFromCache(old);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't save: ${AppErrorState.errorHeadline(e)}")));
    }
  }

  void _apply() {
    final p = _picked!;
    final details = _useDetails && _hasDetails;
    _save(() => widget.editor.applyMetadata(
          widget.series.id,
          MetadataUpdate(
            coverUrl: _useCover ? p.coverUrl : null,
            bannerUrl: _useBanner && _bannerOffered ? p.bannerUrl : null,
            summary: details ? p.description : null,
            genres: details && p.genres.isNotEmpty ? p.genres : null,
            status: details ? p.status : null,
          ),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final p = _picked;
    final nothingChosen = !_useCover &&
        !(_useBanner && _bannerOffered) &&
        !(_useDetails && _hasDetails);
    return SafeArea(
      child: Stack(children: [
        ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            const SheetGrabber(),
            Text('Refresh cover & details', style: AppText.heading(size: 18)),
            const SizedBox(height: 4),
            Text(
              widget.comics
                  ? 'Covers from ComicVine. What you save is shown to everyone.'
                  : 'Covers from AniList and MangaDex. What you save is shown to everyone.',
              style: AppText.body(size: 13, color: AppColors.text60),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => setState(() {
                _picked = null;
                _results = _search();
              }),
              style: AppText.body(size: 14),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: AppColors.fillSubtle,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),
            FutureBuilder<List<CoverCandidate>>(
              future: _results,
              builder: (context, snap) {
                final list = snap.data;
                if (list == null) {
                  return const SizedBox(
                      height: 250, child: Center(child: CircularProgressIndicator.adaptive()));
                }
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text('No matches. Try a shorter or different title.',
                        textAlign: TextAlign.center,
                        style: AppText.body(color: AppColors.text45)),
                  );
                }
                return SizedBox(
                  height: 276,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, i) => _CandidateCard(
                      candidate: list[i],
                      selected: identical(list[i], p),
                      onTap: () => setState(() => _picked = list[i]),
                    ),
                  ),
                );
              },
            ),
            if (p != null) ...[
              const SizedBox(height: 16),
              if (p.description != null)
                Text(p.description!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(size: 13, color: AppColors.text60)),
              if (p.genres.isNotEmpty || p.status != null) ...[
                const SizedBox(height: 6),
                Text(
                  [
                    if (p.status != null) p.status!.name.toUpperCase(),
                    ...p.genres.map((g) => g.toUpperCase()),
                  ].join(' · '),
                  style: AppText.mono(size: 10),
                ),
              ],
              const SizedBox(height: 8),
              _Toggle(
                  label: 'Cover',
                  value: _useCover,
                  onChanged: (v) => setState(() => _useCover = v)),
              if (_bannerOffered)
                _Toggle(
                    label: 'Banner on the series page',
                    value: _useBanner,
                    onChanged: (v) => setState(() => _useBanner = v)),
              if (_hasDetails)
                _Toggle(
                    label: 'Summary, genres and status',
                    value: _useDetails,
                    onChanged: (v) => setState(() => _useDetails = v)),
            ],
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 12, children: [
              InkButton(
                filled: true,
                icon: Icons.check_rounded,
                label: 'Apply',
                height: 44,
                onTap: p == null || nothingChosen || _saving ? null : _apply,
              ),
              if (widget.onReset != null)
                InkButton(
                  icon: Icons.restart_alt_rounded,
                  label: "Use the source's cover",
                  height: 44,
                  onTap: _saving ? null : () => _save(widget.onReset!),
                ),
            ]),
          ],
        ),
        if (_saving)
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.card.withValues(alpha: 0.8),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator.adaptive(),
                  const SizedBox(height: 12),
                  Text('Saving…', style: AppText.body(color: AppColors.text60)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Toggle({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Row(children: [
          Expanded(child: Text(label, style: AppText.body(size: 14))),
          Switch.adaptive(value: value, onChanged: onChanged),
        ]),
      );
}

class _CandidateCard extends StatelessWidget {
  final CoverCandidate candidate;
  final bool selected;
  final VoidCallback onTap;
  const _CandidateCard(
      {required this.candidate, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    return Semantics(
      button: true,
      selected: selected,
      label: '${c.title}, from ${c.source.toLowerCase()}',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 132,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedContainer(
              duration: Motion.scaled(context, Motion.fast),
              height: 190,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                border: Border.all(
                    color: selected ? AppColors.accent : Colors.transparent, width: 3),
              ),
              // An outside image: no server login goes with it.
              child: SeriesCover(imageUrl: c.coverUrl),
            ),
            const SizedBox(height: 6),
            Text(c.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(size: 12, weight: FontWeight.w600)),
            const SizedBox(height: 2),
            _ImageSize(
              url: c.coverUrl,
              prefix: [c.source, if (c.year != null) '${c.year}'].join(' · '),
            ),
          ]),
        ),
      ),
    );
  }
}

/// "ANILIST · 2019 · 1000×1500": the size appears once the image is in.
class _ImageSize extends StatefulWidget {
  final String url;
  final String prefix;
  const _ImageSize({required this.url, required this.prefix});

  @override
  State<_ImageSize> createState() => _ImageSizeState();
}

class _ImageSizeState extends State<_ImageSize> {
  String? _size;
  ImageStream? _stream;
  late final _listener = ImageStreamListener((info, _) {
    if (mounted) setState(() => _size = '${info.image.width}×${info.image.height}');
  }, onError: (_, _) {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream?.removeListener(_listener);
    _stream = CachedNetworkImageProvider(widget.url)
        .resolve(createLocalImageConfiguration(context))
      ..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  // Two lines: on a 132px card one line cut the size off.
  @override
  Widget build(BuildContext context) => Text(
        [widget.prefix, ?_size].join('\n'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppText.mono(size: 9.5),
      );
}
