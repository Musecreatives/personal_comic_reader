import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../backends/suwayomi/suwayomi_backend.dart';
import '../shared/series_cover.dart';

typedef SourceInfo = ({String id, String name, String lang});
typedef SourceManga = ({int id, String title, String thumbnailUrl});
typedef SourcePage = ({List<SourceManga> mangas, bool hasNext});

/// Remembers each source listing fetched this session, so scrolling a shelf
/// off-screen and back (or flipping Popular/Latest back and forth) doesn't
/// ask the source again. A failed fetch isn't remembered, so it can retry.
class SourceListingCache {
  final SuwayomiBackend backend;
  final _cache = <String, Future<SourcePage>>{};

  SourceListingCache(this.backend);

  Future<SourcePage> get(String sourceId, {required bool latest, int page = 1}) {
    final key = '$sourceId|$latest|$page';
    return _cache.putIfAbsent(key, () {
      final future = backend.browseSource(sourceId, page: page, latest: latest);
      // Block body: an arrow would return the removed Future, which isn't
      // this chain's Null type, and throw from inside the error handler.
      future.then((_) {}, onError: (_) {
        _cache.remove(key);
      });
      return future;
    });
  }

  void forget(String sourceId, {required bool latest}) =>
      _cache.remove('$sourceId|$latest|1');
}

/// One shelf per source - its popular or latest titles - so there's
/// something to look at before typing a search. Built lazily as it scrolls
/// into view, so a long source list doesn't fetch everything at once.
class SourceShelves extends StatelessWidget {
  final List<SourceInfo> sources;
  final SourceListingCache cache;
  final void Function(SourceInfo source, SourceManga manga) onOpen;
  final void Function(SourceInfo source) onSeeAll;

  const SourceShelves({
    super.key,
    required this.sources,
    required this.cache,
    required this.onOpen,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text('No sources installed - add extensions in Suwayomi first.',
              textAlign: TextAlign.center,
              style: AppText.body(color: AppColors.text45)),
        ),
      );
    }
    return ListView.builder(
      // Bottom room for the phone's floating nav bar.
      padding: const EdgeInsets.only(top: 6, bottom: 120),
      itemCount: sources.length,
      itemBuilder: (context, i) => _SourceShelf(
        key: ValueKey(sources[i].id),
        source: sources[i],
        cache: cache,
        onOpen: (m) => onOpen(sources[i], m),
        onSeeAll: () => onSeeAll(sources[i]),
      ),
    );
  }
}

class _SourceShelf extends StatefulWidget {
  final SourceInfo source;
  final SourceListingCache cache;
  final ValueChanged<SourceManga> onOpen;
  final VoidCallback onSeeAll;

  const _SourceShelf({
    super.key,
    required this.source,
    required this.cache,
    required this.onOpen,
    required this.onSeeAll,
  });

  @override
  State<_SourceShelf> createState() => _SourceShelfState();
}

class _SourceShelfState extends State<_SourceShelf> {
  bool _latest = false;
  late Future<SourcePage> _page = _fetch();

  Future<SourcePage> _fetch() =>
      widget.cache.get(widget.source.id, latest: _latest);

  void _setLatest(bool latest) {
    if (latest == _latest) return;
    setState(() {
      _latest = latest;
      _page = _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 8, 8),
            child: Row(
              children: [
                Flexible(
                  child: Text(widget.source.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.heading(size: 16)),
                ),
                const SizedBox(width: 10),
                ListingToggle(latest: _latest, onChanged: _setLatest),
                const Spacer(),
                TextButton(
                  onPressed: widget.onSeeAll,
                  child: Text('See all',
                      style: AppText.body(
                          size: 12.5,
                          weight: FontWeight.w600,
                          color: AppColors.accentLink)),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 196,
            child: FutureBuilder<SourcePage>(
              future: _page,
              builder: (context, snap) {
                if (snap.hasError) {
                  return _ShelfMessage(
                    _latest
                        ? "This source doesn't list its latest updates."
                        : "Couldn't reach this source.",
                    onRetry: () {
                      widget.cache.forget(widget.source.id, latest: _latest);
                      setState(() => _page = _fetch());
                    },
                  );
                }
                final mangas = snap.data?.mangas;
                if (mangas == null) return const _ShelfSkeleton();
                if (mangas.isEmpty) {
                  return const _ShelfMessage('Nothing listed.');
                }
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: mangas.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: SizedBox(
                      width: 104,
                      child: SourceMangaCard(
                        manga: mangas[i],
                        onTap: () => widget.onOpen(mangas[i]),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Everything one source lists, as a grid that pages on demand - "See all"
/// from a shelf, or picking that source's chip with nothing typed.
class SourceCatalogGrid extends StatefulWidget {
  final SourceInfo source;
  final SourceListingCache cache;
  final ValueChanged<SourceManga> onOpen;

  const SourceCatalogGrid({
    super.key,
    required this.source,
    required this.cache,
    required this.onOpen,
  });

  @override
  State<SourceCatalogGrid> createState() => _SourceCatalogGridState();
}

class _SourceCatalogGridState extends State<SourceCatalogGrid> {
  bool _latest = false;
  final List<SourceManga> _items = [];
  int _page = 0;
  bool _hasNext = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasNext) return;
    final latest = _latest;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.cache
          .get(widget.source.id, latest: latest, page: _page + 1);
      if (!mounted || latest != _latest) return;
      setState(() {
        _page++;
        _items.addAll(page.mangas);
        _hasNext = page.hasNext;
      });
    } catch (e) {
      if (mounted && latest == _latest) {
        setState(() => _error = latest
            ? "This source doesn't list its latest updates."
            : "Couldn't reach this source.");
      }
    } finally {
      if (mounted && latest == _latest) setState(() => _loading = false);
    }
  }

  void _setLatest(bool latest) {
    if (latest == _latest) return;
    setState(() {
      _latest = latest;
      _items.clear();
      _page = 0;
      _hasNext = true;
      _loading = false;
      _error = null;
    });
    _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: ListingToggle(latest: _latest, onChanged: _setLatest),
        ),
        Expanded(
          child: _items.isEmpty
              ? Center(
                  child: _error != null
                      ? _ShelfMessage(_error!, onRetry: _loadMore)
                      : const CircularProgressIndicator(),
                )
              : NotificationListener<ScrollNotification>(
                  // Fetch the next page a little before the bottom.
                  onNotification: (n) {
                    if (n.metrics.extentAfter < 600) _loadMore();
                    return false;
                  },
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 140,
                      childAspectRatio: 0.56,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: _items.length + (_hasNext ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= _items.length) {
                        return const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      return SourceMangaCard(
                        manga: _items[i],
                        onTap: () => widget.onOpen(_items[i]),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

/// POPULAR / LATEST switch for a source listing.
class ListingToggle extends StatelessWidget {
  final bool latest;
  final ValueChanged<bool> onChanged;
  const ListingToggle({super.key, required this.latest, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget option(String label, bool value) {
      final selected = latest == value;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: Motion.scaled(context, Motion.fast),
          curve: Motion.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: AppText.mono(
                  size: 9.5,
                  color: selected ? Colors.white : AppColors.text60)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.fillSubtle,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [option('POPULAR', false), option('LATEST', true)],
      ),
    );
  }
}

/// A cover with its title underneath.
class SourceMangaCard extends StatelessWidget {
  final SourceManga manga;
  final VoidCallback onTap;
  const SourceMangaCard({super.key, required this.manga, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox.expand(
                    child: SeriesCover(imageUrl: manga.thumbnailUrl),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(manga.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(size: 11.5, weight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShelfSkeleton extends StatelessWidget {
  const _ShelfSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: 6,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: SizedBox(
          width: 104,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.fillSubtle,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 72,
                height: 9,
                decoration: BoxDecoration(
                  color: AppColors.fillSubtle,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShelfMessage extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;
  const _ShelfMessage(this.text, {this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Flexible(
            child: Text(text,
                style: AppText.body(size: 12.5, color: AppColors.text45)),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
