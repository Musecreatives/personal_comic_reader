import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
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

class _SeriesDetail extends StatefulWidget {
  final ReaderBackend backend;
  final String seriesId;

  const _SeriesDetail({required this.backend, required this.seriesId});

  @override
  State<_SeriesDetail> createState() => _SeriesDetailState();
}

class _SeriesDetailState extends State<_SeriesDetail> {
  late Future<Series> _seriesFuture;
  late Future<List<Book>> _booksFuture;

  @override
  void initState() {
    super.initState();
    _seriesFuture = widget.backend.getSeries(widget.seriesId);
    _booksFuture = widget.backend.listBooks(widget.seriesId);
  }

  @override
  Widget build(BuildContext context) {
    final headers = widget.backend.imageHeaders;
    final wide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      body: FutureBuilder<Series>(
        future: _seriesFuture,
        builder: (context, seriesSnapshot) {
          if (!seriesSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final series = seriesSnapshot.data!;
          final header = _SeriesHeader(series: series, headers: headers);
          final bookList = FutureBuilder<List<Book>>(
            future: _booksFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return _BookList(books: snapshot.data!, headers: headers);
            },
          );

          if (wide) {
            return CustomScrollView(
              slivers: [
                SliverAppBar(title: Text(series.title), pinned: true),
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
              SliverAppBar(title: Text(series.title), pinned: true),
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

  const _BookList({required this.books, required this.headers});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: books.length,
      itemBuilder: (context, i) {
        final book = books[i];
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
          trailing: book.completed
              ? const Icon(Icons.check_circle, size: 20)
              : null,
          onTap: () => context.push('/read/${book.id}'),
        );
      },
    );
  }
}
