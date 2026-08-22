import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
import '../shared/series_cover.dart';

enum _ViewMode { grid, list }

class LibraryScreen extends ConsumerStatefulWidget {
  final String libraryId;

  const LibraryScreen({super.key, required this.libraryId});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  _ViewMode _viewMode = _ViewMode.grid;
  bool _unreadOnly = false;
  SeriesSort _sort = SeriesSort.title;
  final _searchController = TextEditingController();
  String _search = '';

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
        libraryId: widget.libraryId,
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
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('$e'))),
      data: (backend) {
        if (backend == null) {
          return const Scaffold(body: Center(child: Text('No server')));
        }
        if (_backend != backend) {
          _backend = backend;
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _loadPage(backend, reset: true));
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Library'),
            actions: [
              IconButton(
                icon: Icon(_viewMode == _ViewMode.grid
                    ? Icons.view_list
                    : Icons.grid_view),
                onPressed: () => setState(() {
                  _viewMode =
                      _viewMode == _ViewMode.grid ? _ViewMode.list : _ViewMode.grid;
                }),
              ),
              PopupMenuButton<SeriesSort>(
                icon: const Icon(Icons.sort),
                onSelected: (sort) {
                  setState(() => _sort = sort);
                  _loadPage(backend, reset: true);
                },
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
              ),
              IconButton(
                icon: Icon(_unreadOnly
                    ? Icons.mark_email_unread
                    : Icons.mark_email_unread_outlined),
                tooltip: 'Unread only',
                onPressed: () {
                  setState(() => _unreadOnly = !_unreadOnly);
                  _loadPage(backend, reset: true);
                },
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search series',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) {
                    _search = value;
                    _loadPage(backend, reset: true);
                  },
                ),
              ),
            ),
          ),
          body: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.pixels >
                  notification.metrics.maxScrollExtent - 400) {
                _loadPage(backend);
              }
              return false;
            },
            child: _viewMode == _ViewMode.grid
                ? _SeriesGrid(items: _items, backend: backend)
                : _SeriesList(items: _items, backend: backend),
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
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 0.62,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final s = items[i];
        return GestureDetector(
          onTap: () => context.push('/series/${s.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SeriesCover(
                        imageUrl: s.thumbnailUrl,
                        headers: backend.imageHeaders,
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
              const SizedBox(height: 6),
              Text(
                s.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SeriesList extends StatelessWidget {
  final List<Series> items;
  final ReaderBackend backend;

  const _SeriesList({required this.items, required this.backend});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final s = items[i];
        return ListTile(
          leading: SizedBox(
            width: 40,
            height: 56,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SeriesCover(
                imageUrl: s.thumbnailUrl,
                headers: backend.imageHeaders,
              ),
            ),
          ),
          title: Text(s.title),
          subtitle: Text('${s.booksCount} books'),
          trailing:
              s.booksUnreadCount > 0 ? _UnreadBadge(count: s.booksUnreadCount) : null,
          onTap: () => context.push('/series/${s.id}'),
        );
      },
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
