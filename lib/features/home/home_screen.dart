import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
import '../shared/series_cover.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backendAsync = ref.watch(activeBackendProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shaddai Reader'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: 'Reading stats',
            onPressed: () => context.push('/stats'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: backendAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => _ErrorState(message: '$e'),
        data: (backend) {
          if (backend == null) {
            return const _NoServerState();
          }
          return _HomeContent(backend: backend);
        },
      ),
    );
  }
}

class _NoServerState extends StatelessWidget {
  const _NoServerState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dns_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('No server configured',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.push('/settings/servers/new'),
              child: const Text('Add a server'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Something went wrong:\n$message',
            textAlign: TextAlign.center),
      ),
    );
  }
}

class _HomeContent extends StatefulWidget {
  final ReaderBackend backend;
  const _HomeContent({required this.backend});

  @override
  State<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<_HomeContent> {
  late Future<List<Library>> _librariesFuture;
  late Future<List<Series>> _continueReadingFuture;
  late Future<List<Book>> _recentlyAddedFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _librariesFuture = widget.backend.listLibraries();
    _continueReadingFuture = widget.backend.continueReading();
    _recentlyAddedFuture = widget.backend.recentlyAdded();
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait(
        [_librariesFuture, _continueReadingFuture, _recentlyAddedFuture]);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _SeriesRow(
            title: 'Continue Reading',
            future: _continueReadingFuture,
            headers: widget.backend.imageHeaders,
          ),
          _BookRow(
            title: 'Recently Added',
            future: _recentlyAddedFuture,
            headers: widget.backend.imageHeaders,
          ),
          FutureBuilder<List<Library>>(
            future: _librariesFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Libraries',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    ...snapshot.data!.map(
                      (lib) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(lib.name),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/library/${Uri.encodeComponent(lib.id)}'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SeriesRow extends StatelessWidget {
  final String title;
  final Future<List<Series>> future;
  final Map<String, String> headers;

  const _SeriesRow(
      {required this.title, required this.future, required this.headers});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Series>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
              height: 100, child: Center(child: CircularProgressIndicator()));
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) return const SizedBox.shrink();
        return _HorizontalRow(
          title: title,
          count: items.length,
          itemBuilder: (context, i) {
            final s = items[i];
            return _CoverTile(
              imageUrl: s.thumbnailUrl,
              headers: headers,
              label: s.title,
              onTap: () => context.push('/series/${Uri.encodeComponent(s.id)}'),
            );
          },
        );
      },
    );
  }
}

class _BookRow extends StatelessWidget {
  final String title;
  final Future<List<Book>> future;
  final Map<String, String> headers;

  const _BookRow(
      {required this.title, required this.future, required this.headers});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Book>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
              height: 100, child: Center(child: CircularProgressIndicator()));
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) return const SizedBox.shrink();
        return _HorizontalRow(
          title: title,
          count: items.length,
          itemBuilder: (context, i) {
            final b = items[i];
            return _CoverTile(
              imageUrl: b.thumbnailUrl,
              headers: headers,
              label: b.title,
              onTap: () => context.push('/series/${Uri.encodeComponent(b.seriesId)}'),
            );
          },
        );
      },
    );
  }
}

class _HorizontalRow extends StatelessWidget {
  final String title;
  final int count;
  final Widget Function(BuildContext, int) itemBuilder;

  const _HorizontalRow({
    required this.title,
    required this.count,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: count,
            itemBuilder: itemBuilder,
          ),
        ),
      ],
    );
  }
}

class _CoverTile extends StatelessWidget {
  final String? imageUrl;
  final Map<String, String> headers;
  final String label;
  final VoidCallback onTap;

  const _CoverTile({
    required this.imageUrl,
    required this.headers,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SeriesCover(imageUrl: imageUrl, headers: headers),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
