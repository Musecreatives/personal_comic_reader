import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
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
  bool _newestFirst = false;

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
      backgroundColor: AppColors.page,
      body: FutureBuilder<Series>(
        future: _seriesFuture,
        builder: (context, seriesSnapshot) {
          if (seriesSnapshot.hasError) {
            return Center(
                child: Text('${seriesSnapshot.error}',
                    style: AppText.body(color: AppColors.text60)));
          }
          if (!seriesSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final series = seriesSnapshot.data!;
          final seriesTasks =
              tasks.where((t) => t.seriesId == widget.seriesId).toList();

          final header = _SeriesHeader(
            series: series,
            headers: headers,
            downloadedCount: seriesTasks
                .where((t) => t.state == DownloadState.done)
                .length,
            onDownloadAll: () => _downloadSeries(series),
          );

          final bookList = FutureBuilder<List<Book>>(
            future: _booksFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                      child: Text('${snapshot.error}',
                          style: AppText.body(color: AppColors.text60))),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final books = List<Book>.from(snapshot.data!);
              if (_newestFirst) books.reversed;
              final ordered = _newestFirst ? books.reversed.toList() : books;
              return _BookList(
                books: ordered,
                headers: headers,
                tasks: tasks,
                newestFirst: _newestFirst,
                onToggleSort: () =>
                    setState(() => _newestFirst = !_newestFirst),
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

          if (wide) {
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 360, child: header),
                      Expanded(child: bookList),
                    ],
                  ),
                ),
              ],
            );
          }

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: header),
              SliverToBoxAdapter(child: bookList),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
  final int downloadedCount;
  final VoidCallback onDownloadAll;

  const _SeriesHeader({
    required this.series,
    required this.headers,
    required this.downloadedCount,
    required this.onDownloadAll,
  });

  @override
  Widget build(BuildContext context) {
    final progressPct = series.booksCount == 0
        ? 0
        : ((series.booksReadCount / series.booksCount) * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 326,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SeriesCover(imageUrl: series.thumbnailUrl, headers: headers),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AppColors.page,
                      AppColors.page.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                    stops: const [0.04, 0.44, 0.8],
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                child: _BackButton(onTap: () => context.pop()),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 100,
                      height: 146,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: DecoratedBox(
                          decoration:
                              BoxDecoration(border: Border.all(color: AppColors.borderStrong)),
                          child: SeriesCover(
                              imageUrl: series.thumbnailUrl, headers: headers),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            series.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.largeTitle(size: 26),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _Pill(
                                label: series.isFullyRead ? 'COMPLETE' : 'READING',
                                color: series.isFullyRead
                                    ? AppColors.suwayomiText
                                    : AppColors.accentLink,
                                bg: series.isFullyRead
                                    ? AppColors.suwayomi.withValues(alpha: 0.16)
                                    : AppColors.accent.withValues(alpha: 0.16),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Read',
                  filled: true,
                  onTap: () {},
                ),
              ),
              const SizedBox(width: 10),
              _ActionIconButton(
                  icon: Icons.download_outlined, onTap: onDownloadAll),
              const SizedBox(width: 10),
              const _ActionIconButton(icon: Icons.bookmark_border),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Row(
            children: [
              _Stat(value: '${series.booksCount}', label: 'VOLUMES'),
              const SizedBox(width: 22),
              _Stat(value: '${series.booksUnreadCount}', label: 'UNREAD'),
              const SizedBox(width: 22),
              _Stat(value: '$progressPct%', label: 'PROGRESS'),
              const SizedBox(width: 22),
              _Stat(value: '$downloadedCount', label: 'ON DEVICE'),
            ],
          ),
        ),
        if (series.summary != null && series.summary!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              series.summary!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(size: 13, color: AppColors.text60, weight: FontWeight.w400),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.canvas.withValues(alpha: 0.7),
      shape: const CircleBorder(side: BorderSide(color: Color(0xFF223349))),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 36,
          height: 36,
          child: Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: Colors.white),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const _Pill({required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: AppText.mono(size: 9, color: color)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _ActionButton(
      {required this.icon, required this.label, this.filled = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AppColors.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: filled ? null : Border.all(color: AppColors.borderStrong),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: filled ? Colors.white : AppColors.text),
              const SizedBox(width: 8),
              Text(label,
                  style: AppText.body(
                      size: 15,
                      weight: FontWeight.w600,
                      color: filled ? Colors.white : AppColors.text)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _ActionIconButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.borderStrong),
          ),
          child: Icon(icon, size: 18, color: AppColors.text),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppText.heading(size: 17)),
        const SizedBox(height: 5),
        Text(label, style: AppText.mono(size: 9)),
      ],
    );
  }
}

class _BookList extends StatelessWidget {
  final List<Book> books;
  final Map<String, String> headers;
  final List<DownloadTask> tasks;
  final bool newestFirst;
  final VoidCallback onToggleSort;
  final ValueChanged<Book> onDownloadBook;

  const _BookList({
    required this.books,
    required this.headers,
    required this.tasks,
    required this.newestFirst,
    required this.onToggleSort,
    required this.onDownloadBook,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Chapters', style: AppText.heading(size: 17)),
              Material(
                color: AppColors.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onToggleSort,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: Text(
                      newestFirst ? 'NEWEST FIRST' : 'OLDEST FIRST',
                      style: AppText.mono(size: 10, color: AppColors.accentLink),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: books.length,
          itemBuilder: (context, i) {
            final book = books[i];
            final task = tasks.where((t) => t.bookId == book.id).firstOrNull;
            return _ChapterRow(
              book: book,
              headers: headers,
              task: task,
              onDownload: () => onDownloadBook(book),
            );
          },
        ),
      ],
    );
  }
}

class _ChapterRow extends StatelessWidget {
  final Book book;
  final Map<String, String> headers;
  final DownloadTask? task;
  final VoidCallback onDownload;

  const _ChapterRow({
    required this.book,
    required this.headers,
    required this.task,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final isInProgress = !book.completed && (book.readProgressPage ?? 0) > 0;
    final meta = book.completed
        ? '${book.pageCount} PAGES · READ'
        : isInProgress
            ? 'PAGE ${book.readProgressPage} OF ${book.pageCount}'
            : task?.state == DownloadState.done
                ? '${book.pageCount} PAGES · DOWNLOADED'
                : '${book.pageCount} PAGES · ON SERVER';

    return InkWell(
      onTap: () => context.push('/read/${Uri.encodeComponent(book.id)}'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text('CH ${book.number}',
                  style: AppText.mono(size: 10, color: AppColors.accentLink)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(size: 15)),
                  const SizedBox(height: 4),
                  Text(meta, style: AppText.mono(size: 9.5)),
                ],
              ),
            ),
            if (book.completed)
              Icon(Icons.check, size: 16, color: AppColors.suwayomiText)
            else if (task != null && task!.state != DownloadState.done)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: task!.progress == 0 ? null : task!.progress,
                ),
              )
            else if (task?.state == DownloadState.done)
              Icon(Icons.download_done, size: 16, color: AppColors.text45)
            else
              InkWell(
                onTap: onDownload,
                child: Icon(Icons.chevron_right, size: 18, color: AppColors.text30),
              ),
          ],
        ),
      ),
    );
  }
}
