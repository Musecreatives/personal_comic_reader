import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
import '../../core/downloads/download_models.dart';
import '../shared/series_cover.dart';

class SeriesScreen extends ConsumerWidget {
  final String seriesId;

  const SeriesScreen({super.key, required this.seriesId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backendAsync = ref.watch(activeBackendProvider);

    return backendAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('$e'))),
      data: (backend) {
        if (backend == null) {
          return const Scaffold(body: Center(child: Text('No server')));
        }
        return _SeriesDetail(backend: backend, seriesId: seriesId);
      },
    );
  }
}

class _SeriesDetail extends ConsumerStatefulWidget {
  final ReaderBackend backend;
  final String seriesId;

  const _SeriesDetail({required this.backend, required this.seriesId});

  @override
  ConsumerState<_SeriesDetail> createState() => _SeriesDetailState();
}

class _SeriesDetailState extends ConsumerState<_SeriesDetail> {
  late Future<Series> _seriesFuture;
  late Future<List<Book>> _booksFuture;

  @override
  void initState() {
    super.initState();
    _seriesFuture = widget.backend.getSeries(widget.seriesId);
    _booksFuture = widget.backend.listBooks(widget.seriesId);
  }

  Future<void> _downloadSeries(Series series) async {
    final books = await _booksFuture;
    await ref.read(downloadManagerProvider).enqueueBooks(
        widget.backend, books, widget.seriesId, series.title);
  }

  @override
  Widget build(BuildContext context) {
    final headers = widget.backend.imageHeaders;
    final wide = MediaQuery.of(context).size.width > 700;
    final tasksAsync = ref.watch(downloadQueueProvider);
    final tasks = tasksAsync.valueOrNull ?? const <DownloadTask>[];

    return Scaffold(
      body: FutureBuilder<Series>(
        future: _seriesFuture,
        builder: (context, seriesSnapshot) {
          if (seriesSnapshot.hasError) {
            return Center(child: Text('${seriesSnapshot.error}'));
          }
          if (!seriesSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final series = seriesSnapshot.data!;
          final header = _SeriesHeader(series: series, headers: headers);
          final bookList = FutureBuilder<List<Book>>(
            future: _booksFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text('${snapshot.error}')),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return _BookList(
                books: snapshot.data!,
                headers: headers,
                tasks: tasks,
                onDownloadBook: (book) => ref.read(downloadManagerProvider).enqueueBook(
                      widget.backend,
                      bookId: book.id,
                      seriesId: widget.seriesId,
                      seriesTitle: series.title,
                      title: book.title,
                      totalPages: book.pageCount,
                    ),
              );
            },
          );

          final appBar = SliverAppBar(
            title: Text(series.title),
            pinned: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.download_outlined),
                tooltip: 'Download series',
                onPressed: () => _downloadSeries(series),
              ),
            ],
          );

          if (wide) {
            return CustomScrollView(
              slivers: [
                appBar,
                SliverToBoxAdapter(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 320, child: header),
                      Expanded(child: bookList),
                    ],
                  ),
                ),
              ],
            );
          }

          return CustomScrollView(
            slivers: [
              appBar,
              SliverToBoxAdapter(child: header),
              SliverToBoxAdapter(child: bookList),
            ],
          );
        },
      ),
    );
  }
}

class _SeriesHeader extends StatelessWidget {
  final Series series;
  final Map<String, String> headers;

  const _SeriesHeader({required this.series, required this.headers});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 0.66,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SeriesCover(
                  imageUrl: series.thumbnailUrl, headers: headers),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${series.booksReadCount} / ${series.booksCount} read',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          if (series.summary != null && series.summary!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(series.summary!),
          ],
        ],
      ),
    );
  }
}

class _BookList extends StatelessWidget {
  final List<Book> books;
  final Map<String, String> headers;
  final List<DownloadTask> tasks;
  final ValueChanged<Book> onDownloadBook;

  const _BookList({
    required this.books,
    required this.headers,
    required this.tasks,
    required this.onDownloadBook,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: books.length,
      itemBuilder: (context, i) {
        final book = books[i];
        final task = tasks.where((t) => t.bookId == book.id).firstOrNull;
        return ListTile(
          leading: SizedBox(
            width: 40,
            height: 56,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SeriesCover(
                  imageUrl: book.thumbnailUrl, headers: headers),
            ),
          ),
          title: Text(book.title),
          subtitle: LinearProgressIndicator(
            value: book.completed ? 1.0 : book.progressRatio,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (book.completed)
                const Icon(Icons.check_circle, size: 20)
              else if (task != null)
                _DownloadStateIcon(task: task)
              else
                IconButton(
                  icon: const Icon(Icons.download_outlined, size: 20),
                  onPressed: () => onDownloadBook(book),
                ),
            ],
          ),
          onTap: () => context.push('/read/${Uri.encodeComponent(book.id)}'),
        );
      },
    );
  }
}

class _DownloadStateIcon extends StatelessWidget {
  final DownloadTask task;
  const _DownloadStateIcon({required this.task});

  @override
  Widget build(BuildContext context) {
    switch (task.state) {
      case DownloadState.done:
        return const Icon(Icons.download_done, size: 20);
      case DownloadState.failed:
        return const Icon(Icons.error_outline, size: 20, color: Colors.redAccent);
      case DownloadState.paused:
        return const Icon(Icons.pause_circle_outline, size: 20);
      case DownloadState.queued:
      case DownloadState.running:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: task.progress == 0 ? null : task.progress,
          ),
        );
    }
  }
}
