import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
import '../shared/error_state.dart';
import '../shared/series_cover.dart';

enum _ViewMode { grid, list }

class LibraryScreen extends ConsumerStatefulWidget {
  final String libraryId;

  const LibraryScreen({super.key, required this.libraryId});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  static const _wideBreakpoint = 800;

  _ViewMode _viewMode = _ViewMode.grid;
  bool _unreadOnly = false;
  SeriesSort _sort = SeriesSort.title;
  final _searchController = TextEditingController();
  String _search = '';

  late String _libraryId = widget.libraryId;
  Future<List<Library>>? _librariesFuture;

  final List<Series> _items = [];
  int _page = 0;
  bool _loading = false;
  bool _hasNext = true;
  ReaderBackend? _backend;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
        _hasNext = true;
      });
    }
    if (!_hasNext) return;

    setState(() => _loading = true);
    try {
      final result = await backend.listSeries(
        libraryId: _libraryId,
        page: _page,
        sort: _sort,
        unreadOnly: _unreadOnly,
        search: _search.isEmpty ? null : _search,
      );
      setState(() {
        _items.addAll(result.items);
        _hasNext = result.hasNext;
        _page++;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
            body: Center(
                child: Text('No server',
                    style: AppText.body(color: AppColors.text60))),
          );
        }
        if (_backend != backend) {
          _backend = backend;
          _librariesFuture = null;
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _loadPage(backend, reset: true));
        }

        final wide = MediaQuery.of(context).size.width >= _wideBreakpoint;
        if (wide) _librariesFuture ??= backend.listLibraries();

        final content = Scaffold(
          backgroundColor: AppColors.page,
          body: SafeArea(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.pixels >
                    notification.metrics.maxScrollExtent - 400) {
                  _loadPage(backend);
                }
                return false;
              },
              child: CustomScrollView(
                slivers: [
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
                      count: _items.length,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: _viewMode == _ViewMode.grid
                        ? _SeriesGrid(items: _items, backend: backend)
                        : _SeriesList(items: _items, backend: backend),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ),
        );

        if (!wide) return content;

        return Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 240,
                child: _LibrarySidebar(
                  librariesFuture: _librariesFuture!,
                  selectedId: _libraryId,
                  onSelect: _selectLibrary,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }
}

class _SeriesGrid extends StatelessWidget {
  final List<Series> items;
  final ReaderBackend backend;

  const _SeriesGrid({required this.items, required this.backend});

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.62,
        crossAxisSpacing: 12,
        mainAxisSpacing: 18,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final s = items[i];
          return GestureDetector(
            onTap: () => context.push('/series/${Uri.encodeComponent(s.id)}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: SeriesCover(
                            imageUrl: s.thumbnailUrl,
                            headers: backend.imageHeaders,
                          ),
                        ),
                      ),
                      if (s.booksUnreadCount > 0)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: _UnreadBadge(count: s.booksUnreadCount),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(size: 11.5, weight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text('${s.booksCount} VOL', style: AppText.mono(size: 9.5)),
              ],
            ),
          );
        },
        childCount: items.length,
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
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SeriesCover(
                        imageUrl: s.thumbnailUrl,
                        headers: backend.imageHeaders,
                      ),
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
                        Text('${s.booksCount} VOL', style: AppText.mono(size: 10.5)),
                      ],
                    ),
                  ),
                  if (s.booksUnreadCount > 0)
                    _UnreadBadge(count: s.booksUnreadCount)
                  else
                    Icon(Icons.check, size: 16, color: AppColors.suwayomiText),
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
  final int count;

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
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Library', style: AppText.largeTitle()),
              Row(
                children: [
                  _HeaderIconButton(
                    icon: viewMode == _ViewMode.grid
                        ? Icons.view_list_outlined
                        : Icons.grid_view_rounded,
                    onTap: onToggleView,
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<SeriesSort>(
                    onSelected: onSort,
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: SeriesSort.title, child: Text('Title')),
                      PopupMenuItem(
                          value: SeriesSort.dateAdded, child: Text('Date added')),
                      PopupMenuItem(
                          value: SeriesSort.dateUpdated,
                          child: Text('Date updated')),
                      PopupMenuItem(
                          value: SeriesSort.releaseDate,
                          child: Text('Release date')),
                    ],
                    child: const _HeaderIconButton(icon: Icons.sort_rounded),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 38,
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
                    controller: searchController,
                    onSubmitted: onSearch,
                    style: AppText.body(size: 14),
                    decoration: InputDecoration(
                      hintText: 'Search series',
                      hintStyle: AppText.body(size: 14, color: AppColors.text45),
                      isDense: true,
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
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
            ],
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
              Text(sourceName,
                  style: AppText.body(size: 15, weight: FontWeight.w600)),
              const Spacer(),
              Text('$count SERIES', style: AppText.mono(size: 10)),
            ],
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _HeaderIconButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.fillSubtle,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 17, color: AppColors.text),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accent : AppColors.fillSubtle,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Text(
            label,
            style: AppText.body(
              size: 11.5,
              weight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.text60,
            ),
          ),
        ),
      ),
    );
  }
}

/// Wide-screen (iPad/desktop) sidebar: every library, so switching doesn't
/// need a full navigation round trip back through Home.
class _LibrarySidebar extends StatelessWidget {
  final Future<List<Library>> librariesFuture;
  final String selectedId;
  final ValueChanged<String> onSelect;

  const _LibrarySidebar({
    required this.librariesFuture,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Libraries',
                style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Library>>(
            future: librariesFuture,
            builder: (context, snapshot) {
              final libraries = snapshot.data ?? const <Library>[];
              return ListView.builder(
                itemCount: libraries.length,
                itemBuilder: (context, i) {
                  final lib = libraries[i];
                  final selected = lib.id == selectedId;
                  return ListTile(
                    selected: selected,
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(lib.name),
                    onTap: () => onSelect(lib.id),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
    );
  }
}
