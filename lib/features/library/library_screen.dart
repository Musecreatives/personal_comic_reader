import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/brand_seal.dart';
import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
import '../shared/ink_chip.dart';
import '../shared/error_state.dart';
import '../shared/series_cover.dart';

enum _ViewMode { grid, list }

/// Covers stay about 110-160 wide: three across on a phone, four on a
/// portrait tablet, six on a landscape one.
const _gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 160,
  childAspectRatio: 0.56,
  crossAxisSpacing: 12,
  mainAxisSpacing: 18,
);

class LibraryScreen extends ConsumerStatefulWidget {
  /// Null when opened as the "Library" nav tab root (`/library`) rather
  /// than a specific deep link (`/library/:id`) - in that case the first
  /// library of whichever server is active is resolved automatically, and
  /// a server switcher is shown if more than one server is configured
  /// (e.g. one manga server, one comics server).
  final String? libraryId;

  const LibraryScreen({super.key, this.libraryId});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {

  _ViewMode _viewMode = _ViewMode.grid;
  bool _unreadOnly = false;
  SeriesSort _sort = SeriesSort.title;
  final _searchController = TextEditingController();
  String _search = '';

  String? _libraryId;
  Future<List<Library>>? _librariesFuture;

  final List<Series> _items = [];
  int _page = 0;
  int _total = 0;
  bool _loading = false;
  bool _hasNext = true;
  Object? _error;
  ReaderBackend? _backend;

  @override
  void initState() {
    super.initState();
    _libraryId = widget.libraryId;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Fetches the active backend's own library list and picks the first one
  /// - used when this screen is opened as the tab root (no id in the
  /// route) or after switching servers, where whatever [_libraryId] was
  /// set to (if anything) belongs to a different backend.
  Future<void> _resolveDefaultLibrary(ReaderBackend backend) async {
    final List<Library> libs;
    try {
      libs = await backend.listLibraries();
    } catch (e) {
      if (mounted && _backend == backend) setState(() => _error = e);
      return;
    }
    if (!mounted || _backend != backend) return;
    if (libs.isEmpty) {
      setState(() {
        _libraryId = null;
        _hasNext = false;
      });
      return;
    }
    setState(() => _libraryId = libs.first.id);
    _loadPage(backend, reset: true);
  }

  void _selectLibrary(String libraryId) {
    if (libraryId == _libraryId) return;
    setState(() => _libraryId = libraryId);
    if (_backend != null) _loadPage(_backend!, reset: true);
  }

  Future<void> _loadPage(ReaderBackend backend, {bool reset = false}) async {
    if (_loading) return;
    if (reset) {
      setState(() {
        _items.clear();
        _page = 0;
        _total = 0;
        _hasNext = true;
      });
    }
    if (!_hasNext) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await backend.listSeries(
        libraryId: _libraryId,
        page: _page,
        sort: _sort,
        unreadOnly: _unreadOnly,
        search: _search.isEmpty ? null : _search,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _total = result.totalElements;
        _hasNext = result.hasNext;
        _page++;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clearFilters(ReaderBackend backend) {
    _searchController.clear();
    setState(() {
      _search = '';
      _unreadOnly = false;
    });
    _loadPage(backend, reset: true);
  }

  /// Only Komga reports a grand total; the others count the page they
  /// sent, so while more pages remain the label reads "40+".
  String get _countLabel {
    final shown = math.max(_total, _items.length);
    return _hasNext && shown == _items.length && shown > 0 ? '$shown+' : '$shown';
  }

  @override
  Widget build(BuildContext context) {
    final backendAsync = ref.watch(activeBackendProvider);

    return backendAsync.when(
      loading: () => Scaffold(
          backgroundColor: AppColors.page,
          body: const Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(
        backgroundColor: AppColors.page,
        body: AppErrorState(
          error: e,
          onRetry: () => ref.invalidate(activeBackendProvider),
        ),
      ),
      data: (backend) {
        if (backend == null) {
          return Scaffold(
            backgroundColor: AppColors.page,
            body: EmptyState(
              title: 'No server yet',
              message: 'Add your Komga, Kavita or Suwayomi server to fill these shelves.',
              action: InkButton(
                filled: true,
                icon: Icons.add,
                label: 'Add a server',
                onTap: () => context.push('/settings/servers/new'),
              ),
            ),
          );
        }
        if (_backend != backend) {
          final previousBackend = _backend;
          _backend = backend;
          _librariesFuture = null;
          if (_libraryId == null || previousBackend != null) {
            // Tab root (no deep-linked id) or an actual server switch -
            // whatever _libraryId held (if anything) belongs to a
            // different backend, so resolve a fresh default.
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _resolveDefaultLibrary(backend));
          } else {
            // First-ever build with an explicit deep-linked id - use it.
            WidgetsBinding.instance.addPostFrameCallback(
                (_) => _loadPage(backend, reset: true));
          }
        }

        // Needed on phones too: the category chips under the search field.
        _librariesFuture ??= backend.listLibraries();

        return Scaffold(
          backgroundColor: AppColors.page,
          body: SafeArea(
            child: RefreshIndicator.adaptive(
              color: AppColors.accent,
              onRefresh: () => _loadPage(backend, reset: true),
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (_error == null &&
                      notification.metrics.pixels >
                          notification.metrics.maxScrollExtent - 400) {
                    _loadPage(backend);
                  }
                  return false;
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (widget.libraryId == null)
                      SliverToBoxAdapter(child: _ServerSwitcher()),
                    SliverToBoxAdapter(
                      child: _LibraryHeader(
                        viewMode: _viewMode,
                        onToggleView: () => setState(() {
                          _viewMode = _viewMode == _ViewMode.grid
                              ? _ViewMode.list
                              : _ViewMode.grid;
                        }),
                        sort: _sort,
                        onSort: (sort) {
                          setState(() => _sort = sort);
                          _loadPage(backend, reset: true);
                        },
                        searchController: _searchController,
                        onSearch: (value) {
                          _search = value;
                          _loadPage(backend, reset: true);
                        },
                        unreadOnly: _unreadOnly,
                        onToggleUnread: () {
                          setState(() => _unreadOnly = !_unreadOnly);
                          _loadPage(backend, reset: true);
                        },
                        sourceColor: AppColors.sourceColor(backend.config.type.name),
                        sourceName: backend.config.name,
                        countLabel: _countLabel,
                        librariesFuture: _librariesFuture,
                        selectedLibraryId: _libraryId,
                        onSelectLibrary: _selectLibrary,
                      ),
                    ),
                    ..._body(backend),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _body(ReaderBackend backend) {
    if (_items.isEmpty) {
      if (_error != null) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: AppErrorState(
              error: _error!,
              onRetry: () => _libraryId == null
                  ? _resolveDefaultLibrary(backend)
                  : _loadPage(backend, reset: true),
            ),
          ),
        ];
      }
      if (_loading || _hasNext) {
        return [
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            sliver: _SkeletonGrid(),
          ),
        ];
      }
      final filtered = _unreadOnly || _search.isNotEmpty;
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            title: filtered ? 'Nothing matches' : 'This shelf is empty',
            message: filtered
                ? 'No series match these filters.'
                : 'Series you add on the server show up here.',
            action: filtered
                ? InkButton(
                    icon: Icons.filter_alt_off_outlined,
                    label: 'Clear filters',
                    onTap: () => _clearFilters(backend),
                  )
                : null,
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: _viewMode == _ViewMode.grid
            ? _SeriesGrid(items: _items, backend: backend)
            : _SeriesList(items: _items, backend: backend),
      ),
      if (_loading)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 20),
            child: Center(child: CircularProgressIndicator.adaptive()),
          ),
        )
      else if (_error != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(children: [
              Text(AppErrorState.errorHeadline(_error!),
                  textAlign: TextAlign.center,
                  style: AppText.body(size: 13, color: AppColors.text60)),
              const SizedBox(height: 10),
              InkButton(
                icon: Icons.refresh,
                label: 'Load more',
                height: 44,
                onTap: () => _loadPage(backend),
              ),
            ]),
          ),
        ),
    ];
  }
}

class _SeriesGrid extends StatelessWidget {
  final List<Series> items;
  final ReaderBackend backend;

  const _SeriesGrid({required this.items, required this.backend});

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: _gridDelegate,
      delegate: SliverChildBuilderDelegate(
        (context, i) => _SeriesTile(series: items[i], backend: backend),
        childCount: items.length,
      ),
    );
  }
}

class _SeriesTile extends StatelessWidget {
  final Series series;
  final ReaderBackend backend;

  const _SeriesTile({required this.series, required this.backend});

  @override
  Widget build(BuildContext context) {
    final s = series;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: PressScale(
          child: GestureDetector(
            onTap: () => context.push('/series/${Uri.encodeComponent(s.id)}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      SeriesCover(
                        imageUrl: s.thumbnailUrl,
                        headers: backend.imageHeaders,
                      ),
                      if (s.booksUnreadCount > 0)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: _UnreadBadge(count: s.booksUnreadCount),
                        ),
                      if (s.isFullyRead)
                        const Positioned(top: 0, right: 0, child: _FinishedMark()),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                _ReadProgress(series: s),
                const SizedBox(height: 6),
                Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(size: 12, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(_volumesLabel(s), maxLines: 1, style: AppText.mono(size: 9.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _volumesLabel(Series s) => s.booksReadCount > 0 && !s.isFullyRead
    ? '${s.booksReadCount}/${s.booksCount} VOL'
    : '${s.booksCount} VOL';

/// Placeholder shelf while the first page loads: card-coloured covers in
/// the same grid, so nothing jumps when the real ones arrive.
class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid();

  @override
  Widget build(BuildContext context) {
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
          widthFactor: widthFactor,
          child: Container(height: height, color: AppColors.card),
        );
    return SliverGrid(
      gridDelegate: _gridDelegate,
      delegate: SliverChildBuilderDelegate(
        (context, i) => ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Container(color: AppColors.card)),
              const SizedBox(height: 16),
              bar(0.8, 10),
              const SizedBox(height: 6),
              bar(0.4, 8),
            ],
          ),
        ),
        childCount: 12,
      ),
    );
  }
}

class _SeriesList extends StatelessWidget {
  final List<Series> items;
  final ReaderBackend backend;

  const _SeriesList({required this.items, required this.backend});

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final s = items[i];
          return InkWell(
            onTap: () => context.push('/series/${Uri.encodeComponent(s.id)}'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 46,
                    height: 66,
                    child: SeriesCover(
                      imageUrl: s.thumbnailUrl,
                      headers: backend.imageHeaders,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body(
                                size: 14.5, weight: FontWeight.w500)),
                        const SizedBox(height: 5),
                        Text(_volumesLabel(s), style: AppText.mono(size: 10.5)),
                        const SizedBox(height: 8),
                        _ReadProgress(series: s),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  if (s.booksUnreadCount > 0)
                    _UnreadBadge(count: s.booksUnreadCount)
                  else if (s.isFullyRead)
                    const _FinishedMark(),
                ],
              ),
            ),
          );
        },
        childCount: items.length,
      ),
    );
  }
}

/// How much of a series has been read: the 4px progress track
/// (DESIGN.md "progress-track" / "progress-fill").
class _ReadProgress extends StatelessWidget {
  final Series series;
  const _ReadProgress({required this.series});

  @override
  Widget build(BuildContext context) {
    final count = series.booksCount;
    final value = count == 0 ? 0.0 : series.booksReadCount / count;
    return Semantics(
      label: '${series.booksReadCount} of $count read',
      child: ExcludeSemantics(
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          minHeight: 4,
          color: AppColors.accent,
          backgroundColor: AppColors.track,
        ),
      ),
    );
  }
}

/// A small hanko stamp on a finished series: identity ink, not a control.
class _FinishedMark extends StatelessWidget {
  const _FinishedMark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Finished',
      child: Container(
        width: 20,
        height: 20,
        color: AppColors.seal,
        alignment: Alignment.center,
        child: const Icon(Icons.check, size: 14, color: AppColors.onSeal),
      ),
    );
  }
}

/// One tap to flip between configured servers when opened as the Library
/// nav tab - e.g. a manga server and a comics server. Hidden entirely when
/// only one server is configured (nothing to switch between).
class _ServerSwitcher extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serverListProvider);
    final activeId = ref.watch(activeServerIdProvider);
    if (servers.length < 2) return const SizedBox.shrink();

    // Servers as ink chips with their source dot. Two servers can share a
    // display name, so the type is part of the label.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          for (final server in servers) ...[
            InkChip(
              label: server.type.name == 'local'
                  ? server.name
                  : '${server.name} · ${server.type.name[0].toUpperCase()}${server.type.name.substring(1)}',
              dot: AppColors.sourceColor(server.type.name),
              selected: server.id == activeId,
              onTap: () async {
                if (server.id == activeId) return;
                await ref.read(serverStoreProvider).setActiveServerId(server.id);
                ref.read(activeServerIdProvider.notifier).state = server.id;
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}


class _LibraryHeader extends StatelessWidget {
  final _ViewMode viewMode;
  final VoidCallback onToggleView;
  final SeriesSort sort;
  final ValueChanged<SeriesSort> onSort;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final bool unreadOnly;
  final VoidCallback onToggleUnread;
  final Color sourceColor;
  final String sourceName;
  final String countLabel;
  final Future<List<Library>>? librariesFuture;
  final String? selectedLibraryId;
  final ValueChanged<String> onSelectLibrary;

  const _LibraryHeader({
    required this.viewMode,
    required this.onToggleView,
    required this.sort,
    required this.onSort,
    required this.searchController,
    required this.onSearch,
    required this.unreadOnly,
    required this.onToggleUnread,
    required this.sourceColor,
    required this.sourceName,
    required this.countLabel,
    required this.librariesFuture,
    required this.selectedLibraryId,
    required this.onSelectLibrary,
  });

  static const _sortLabels = {
    SeriesSort.title: 'Title',
    SeriesSort.dateAdded: 'Date added',
    SeriesSort.dateUpdated: 'Date updated',
    SeriesSort.releaseDate: 'Release date',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Screentone behind the title (DESIGN.md "Screentone": headers).
          CustomPaint(
            painter: Screentone(AppColors.text.withValues(alpha: 0.08)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Library',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.largeTitle()),
                  ),
                  _HeaderIconButton(
                    icon: Icons.search,
                    tooltip: 'Search everywhere',
                    onTap: () => context.push('/search'),
                  ),
                  const SizedBox(width: 4),
                  _HeaderIconButton(
                    icon: viewMode == _ViewMode.grid
                        ? Icons.view_list_outlined
                        : Icons.grid_view_rounded,
                    tooltip: viewMode == _ViewMode.grid ? 'Show as list' : 'Show as grid',
                    onTap: onToggleView,
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<SeriesSort>(
                    tooltip: 'Sort: ${_sortLabels[sort]}',
                    initialValue: sort,
                    onSelected: onSort,
                    itemBuilder: (context) => [
                      for (final entry in _sortLabels.entries)
                        CheckedPopupMenuItem(
                          value: entry.key,
                          checked: entry.key == sort,
                          child: Text(entry.value),
                        ),
                    ],
                    child: const _HeaderIconButton(icon: Icons.sort_rounded),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 44,
            padding: const EdgeInsets.only(left: 12),
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
                    controller: searchController,
                    onSubmitted: onSearch,
                    textInputAction: TextInputAction.search,
                    style: AppText.body(size: 14),
                    decoration: InputDecoration(
                      hintText: 'Search this library',
                      hintStyle: AppText.body(size: 14, color: AppColors.text45),
                      isDense: true,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: searchController,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox(width: 12)
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: Icon(Icons.close, size: 18, color: AppColors.text60),
                          onPressed: () {
                            searchController.clear();
                            onSearch('');
                          },
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 36,
            child: FutureBuilder<List<Library>>(
              future: librariesFuture,
              builder: (context, snapshot) {
                final libraries = snapshot.data ?? const <Library>[];
                return ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  // Let the row scroll out to the screen edge, not the padding.
                  clipBehavior: Clip.none,
                  children: [
                    _FilterChip(label: 'All', selected: !unreadOnly, onTap: () {
                      if (unreadOnly) onToggleUnread();
                    }),
                    const SizedBox(width: 7),
                    _FilterChip(
                      label: 'Unread',
                      selected: unreadOnly,
                      onTap: () {
                        if (!unreadOnly) onToggleUnread();
                      },
                    ),
                    // The collections/categories, as chips at every width.
                    if (libraries.length > 1) ...[
                      const _ChipDivider(),
                      for (final lib in libraries) ...[
                        _FilterChip(
                          label: lib.name,
                          selected: lib.id == selectedLibraryId,
                          tinted: true,
                          onTap: () => onSelectLibrary(lib.id),
                        ),
                        const SizedBox(width: 7),
                      ],
                    ],
                    // Your own collections (they span servers, so they open
                    // on their own page rather than filtering this one).
                    Consumer(builder: (context, ref, _) {
                      ref.watch(collectionsRevisionProvider);
                      final mine = ref.watch(collectionsStoreProvider).list();
                      return Row(children: [
                        const _ChipDivider(),
                        for (final c in mine) ...[
                          _FilterChip(
                            label: c.name,
                            selected: false,
                            onTap: () => context.push('/collections/${c.id}'),
                          ),
                          const SizedBox(width: 7),
                        ],
                        _FilterChip(
                          label: mine.isEmpty ? '+ Collections' : 'All collections',
                          selected: false,
                          onTap: () => context.push('/collections'),
                        ),
                      ]);
                    }),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(color: sourceColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(sourceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(size: 15, weight: FontWeight.w600)),
              ),
              Text('$countLabel SERIES', style: AppText.mono(size: 10)),
            ],
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _ChipDivider extends StatelessWidget {
  const _ChipDivider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        color: AppColors.border,
      );
}

/// A 44px target (the touch minimum) around a 36px filled circle.
class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback? onTap;
  const _HeaderIconButton({required this.icon, this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: Material(
          color: AppColors.fillSubtle,
          shape: const CircleBorder(),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 18, color: AppColors.text),
          ),
        ),
      ),
    );
    // Inside a PopupMenuButton (no onTap) the menu owns the tap and tooltip.
    if (onTap == null) return button;
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: button,
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Selected collections use an outlined, tinted look so they read as a
  /// different kind of choice from the filled All / Unread filters.
  final bool tinted;
  const _FilterChip(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.tinted = false});

  @override
  Widget build(BuildContext context) =>
      InkChip(label: label, selected: selected, onTap: onTap, secondary: tinted);
}

class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$count unread',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: AppText.mono(size: 10.5, weight: FontWeight.w700, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
