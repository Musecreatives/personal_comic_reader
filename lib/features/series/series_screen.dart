import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/platform_style.dart';
import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
import '../../core/comicvine/comicvine_client.dart';
import '../../core/downloads/download_models.dart';
import '../../backends/local/local_backend.dart';
import '../../backends/local/local_library_store.dart';
import '../../backends/suwayomi/suwayomi_backend.dart';
import '../home/home_feed.dart';
import '../local_library/local_library_screen.dart' show localLibraryRevisionProvider;
import 'chapter_actions.dart';
import 'comicvine_match_sheet.dart';
import 'download_sheet.dart';
import 'edit_details_sheet.dart';
import 'linked_sources_sheet.dart';
import 'refresh_cover_sheet.dart';
import '../../core/metadata/cover_candidates.dart';
import '../search/cross_server_search_screen.dart' show searchLocation;
import 'series_actions_sheet.dart';
import '../../core/collections/collection.dart';
import '../collections/collections_screen.dart' show createCollection;
import '../shared/ink_chip.dart';
import '../shared/back_button.dart';
import '../shared/error_state.dart';
import '../shared/series_cover.dart';
import '../shared/app_sheet.dart';

class SeriesScreen extends ConsumerWidget {
  final String seriesId;

  const SeriesScreen({super.key, required this.seriesId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backendAsync = ref.watch(activeBackendProvider);

    return backendAsync.when(
      loading: () => Scaffold(
        backgroundColor: AppColors.page,
        body: const Center(child: CircularProgressIndicator()),
      ),
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
              child: Text(
                'No server',
                style: AppText.body(color: AppColors.text60),
              ),
            ),
          );
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

  // Chapter selection: long-press / Ctrl+click toggles, Shift+click selects a
  // range, right-click opens the menu, Ctrl+A selects all, Esc clears.
  final _selected = <String>{};
  final _focus = FocusNode();
  String? _anchor;
  List<Book> _ordered = const [];

  bool get _selecting => _selected.isNotEmpty;
  List<Book> get _selectedBooks =>
      _ordered.where((b) => _selected.contains(b.id)).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _select(Book b, {bool range = false}) {
    setState(() {
      if (range && _anchor != null) {
        final a = _ordered.indexWhere((x) => x.id == _anchor);
        final z = _ordered.indexWhere((x) => x.id == b.id);
        if (a >= 0 && z >= 0) {
          for (var i = a < z ? a : z; i <= (a < z ? z : a); i++) {
            _selected.add(_ordered[i].id);
          }
          return;
        }
      }
      if (!_selected.remove(b.id)) _selected.add(b.id);
      _anchor = b.id;
    });
    _focus.requestFocus();
  }

  void _onTapBook(Book b) {
    final kb = HardwareKeyboard.instance;
    final shift = kb.isShiftPressed;
    if (shift || kb.isControlPressed || kb.isMetaPressed || _selecting) {
      _select(b, range: shift);
      return;
    }
    context.push('/read/${Uri.encodeComponent(b.id)}');
  }

  void _onLongPressBook(Book b) {
    HapticFeedback.selectionClick();
    _select(b);
  }

  bool _anyDownloaded(Iterable<Book> books, List<DownloadTask> tasks) =>
      books.any(
        (b) =>
            tasks.any((t) => t.bookId == b.id && t.state == DownloadState.done),
      );

  Future<void> _onSecondaryTap(
    Book b,
    Offset at,
    List<DownloadTask> tasks,
  ) async {
    // Right-clicking outside the selection acts on that row alone, like a
    // file manager; right-clicking inside it acts on the whole selection.
    final transient = !_selected.contains(b.id);
    if (transient) {
      setState(() {
        _selected
          ..clear()
          ..add(b.id);
        _anchor = b.id;
      });
    }
    final chosen = _selectedBooks;
    final action = await showChapterMenu(
      context,
      at,
      count: chosen.length,
      anyDownloaded: _anyDownloaded(chosen, tasks),
    );
    if (!mounted) return;
    if (action == null) {
      if (transient) setState(_selected.clear);
      return;
    }
    await _runAction(action, chosen);
  }

  Future<void> _runAction(ChapterAction action, List<Book> chosen) async {
    final backend = widget.backend;
    final manager = ref.read(downloadManagerProvider);
    try {
      final series = await _seriesFuture;
      switch (action) {
        case ChapterAction.markRead:
          for (final b in chosen) {
            await backend.updateProgress(
              b.id,
              page: b.pageCount > 0 ? b.pageCount - 1 : 0,
              completed: true,
            );
          }
        case ChapterAction.markUnread:
          for (final b in chosen) {
            await backend.updateProgress(b.id, page: 0, completed: false);
          }
        case ChapterAction.download:
          await manager.enqueueBooks(
            backend,
            chosen,
            widget.seriesId,
            series.title,
          );
        case ChapterAction.deleteDownload:
          for (final b in chosen) {
            await manager.cancel(b.id);
          }
      }
    } catch (e) {
      _snack("Couldn't do that: $e");
      return;
    }
    if (!mounted) return;
    setState(_selected.clear);
    if (action == ChapterAction.markRead ||
        action == ChapterAction.markUnread) {
      _reloadBooks();
      _reloadSeries();
      ref.invalidate(homeFeedProvider);
    }
    final n = chosen.length;
    _snack(switch (action) {
      ChapterAction.markRead => 'Marked $n as read',
      ChapterAction.markUnread => 'Marked $n as unread',
      ChapterAction.download => 'Downloading $n chapter${n == 1 ? '' : 's'}',
      ChapterAction.deleteDownload => 'Removed $n download${n == 1 ? '' : 's'}',
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape && _selecting) {
      setState(_selected.clear);
      return KeyEventResult.handled;
    }
    final kb = HardwareKeyboard.instance;
    if (key == LogicalKeyboardKey.keyA &&
        (kb.isControlPressed || kb.isMetaPressed) &&
        _ordered.isNotEmpty) {
      setState(() => _selected.addAll(_ordered.map((b) => b.id)));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _load() {
    _seriesFuture = widget.backend.getSeries(widget.seriesId);
    _booksFuture = widget.backend.listBooks(widget.seriesId);
  }

  void _reloadSeries() => setState(() {
    _seriesFuture = widget.backend.getSeries(widget.seriesId);
  });

  void _reloadBooks() => setState(() {
    _booksFuture = widget.backend.listBooks(widget.seriesId);
  });

  /// The download button opens a picker (next 5/10, new since you last read,
  /// all unread, everything, or a checklist) rather than queueing the lot.
  Future<void> _downloadSeries(Series series) async {
    final books = await _booksFuture;
    if (!mounted) return;
    final tasks =
        ref.read(downloadQueueProvider).valueOrNull ?? const <DownloadTask>[];
    // Failed ones can be offered again; anything else is already handled.
    final already = tasks
        .where(
          (t) =>
              t.seriesId == widget.seriesId && t.state != DownloadState.failed,
        )
        .map((t) => t.bookId)
        .toSet();
    await DownloadSheet.show(
      context,
      books: books,
      alreadyIds: already,
      onConfirm: (chosen) async {
        await ref
            .read(downloadManagerProvider)
            .enqueueBooks(
              widget.backend,
              chosen,
              widget.seriesId,
              series.title,
            );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Downloading ${chosen.length} chapter${chosen.length == 1 ? '' : 's'}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// Stop reading / delete downloads / remove from library.
  void _showActions(Series series, int downloadedCount) {
    final backend = widget.backend;
    SeriesActionsSheet.show(
      context,
      title: series.title,
      downloadedCount: downloadedCount,
      canRemoveFromLibrary: backend is SuwayomiBackend,
      onStopReading: () async {
        await ref
            .read(stoppedSeriesStoreProvider)
            .stop('${backend.config.id}|${widget.seriesId}');
        ref.read(stoppedRevisionProvider.notifier).state++;
        _snack('Hidden from Home. It comes back when you read it again.');
      },
      onDeleteDownloads: () async {
        await ref.read(downloadManagerProvider).cancelSeries(widget.seriesId);
        _snack('Downloads removed from this device');
      },
      onRemoveFromLibrary: () async {
        try {
          await (backend as SuwayomiBackend).removeFromLibrary(widget.seriesId);
        } catch (e) {
          _snack("Couldn't remove it: $e");
          return;
        }
        ref.invalidate(homeFeedProvider);
        if (!mounted) return;
        context.popOrHome();
        _snack('Removed from library');
      },
      onEditDetails: backend is LocalBackend ? _editDetails : null,
      onFindOnComicVine: backend is LocalBackend ? _findOnComicVine : null,
      onManageSources: backend is SuwayomiBackend
          ? () => _manageSources(backend, series)
          : null,
      // Manga on the Suwayomi sources; comics through Kapowarr.
      onSearchTitle: () => context.go(searchLocation(series.title,
          mode: backend is SuwayomiBackend ? 'manga' : 'comics')),
      onRefreshCover: backend is SeriesMetadataEditor && ref.read(isOwnerProvider)
          ? () => _refreshCover(backend as SeriesMetadataEditor, series)
          : null,
    );
  }

  /// Owner only. Suwayomi titles are manga, looked up on AniList and
  /// MangaDex; Komga holds comics, looked up on ComicVine when a key is set
  /// (and on the manga catalogues otherwise).
  Future<void> _refreshCover(SeriesMetadataEditor editor, Series series) async {
    final backend = widget.backend;
    final key = backend is SuwayomiBackend
        ? null
        : await ref.read(comicVineKeyStoreProvider).get();
    if (!mounted) return;
    final saved = await showRefreshCoverSheet(
      context,
      editor: editor,
      series: series,
      finder: CoverCandidateFinder(
          comicVine: key == null ? null : ComicVineClient(apiKey: key)),
      comics: key != null,
      onReset: backend is SuwayomiBackend ? () => backend.resetCover(series.id) : null,
    );
    if (saved != true || !mounted) return;
    ref.invalidate(homeFeedProvider);
    _reloadSeries();
    _snack('Cover and details saved');
  }

  /// Main and backup sources. Promoting a backup moves the series to a new
  /// id, so the page reopens on it.
  Future<void> _manageSources(SuwayomiBackend backend, Series series) async {
    final newId = await showLinkedSourcesSheet(
      context,
      backend: backend,
      series: series,
      canEdit: ref.read(isOwnerProvider),
    );
    if (newId == null || !mounted) return;
    ref.invalidate(homeFeedProvider);
    context.pushReplacement('/series/${Uri.encodeComponent(newId)}');
    _snack('Main source switched');
  }

  /// Picks a ComicVine match, then opens Edit details pre-filled with it
  /// (keeping anything ComicVine doesn't have) for the user to confirm.
  Future<void> _findOnComicVine() async {
    final apiKey = await ref.read(comicVineKeyStoreProvider).get();
    if (!mounted) return;
    if (apiKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Add a ComicVine API key in Settings first'),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: () => context.push('/settings/comicvine'),
        ),
      ));
      return;
    }
    final existing =
        ref.read(localLibraryStoreProvider).getSeries(widget.seriesId);
    if (existing == null) return;
    final match = await showComicVineMatchSheet(
      context,
      client: ComicVineClient(apiKey: apiKey),
      query: existing.title,
    );
    if (match == null || !mounted) return;
    await _editDetails(
      heading: 'Review ComicVine details',
      prefill: existing.withDetails(
        title: existing.title,
        summary: match.summary ?? existing.summary,
        writer: match.writer ?? existing.writer,
        artist: match.artist ?? existing.artist,
        publisher: match.publisher ?? existing.publisher,
        year: match.startYear ?? existing.year,
        genres: existing.genres, // ComicVine volumes have none
      ),
    );
  }

  /// Imported series only. [prefill] (a ComicVine match) seeds the form in
  /// place of what's stored; nothing is saved until the user taps Save.
  Future<void> _editDetails({
    LocalSeriesRecord? prefill,
    String heading = 'Edit details',
  }) async {
    final store = ref.read(localLibraryStoreProvider);
    final existing = store.getSeries(widget.seriesId);
    if (existing == null) return;
    final edited = await showEditDetailsSheet(context, prefill ?? existing,
        heading: heading);
    if (edited == null) return;
    await store.putSeries(edited);
    ref.read(localLibraryRevisionProvider.notifier).state++;
    ref.invalidate(homeFeedProvider);
    if (mounted) _reloadSeries();
  }

  Future<void> _renameBook(Book book) async {
    final titleController = TextEditingController(text: book.title);
    final numberController = TextEditingController(text: book.number);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Rename chapter'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
              style: AppText.body(size: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: numberController,
              decoration: const InputDecoration(labelText: 'Chapter number'),
              style: AppText.body(size: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (result != true) return;
    final store = ref.read(localLibraryStoreProvider);
    final existing = store.getBook(book.id);
    if (existing == null) return;
    await store.putBook(existing.copyWith(
      title: titleController.text.trim(),
      number: numberController.text.trim(),
    ));
    _reloadBooks();
  }

  void _showCollectionPicker(BuildContext context, String seriesId) {
    showAppSheet<void>(
      context: context,
      grabber: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final store = ref.read(collectionsStoreProvider);
            final collections = store.list();
            // Recorded with its server, so a collection can mix servers and
            // still open the right series on every synced device.
            final entry =
                collectionEntry(widget.backend.config.portableKey, seriesId);
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Add to collection',
                            style: AppText.body(size: 16, weight: FontWeight.w600),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final id = await createCollection(context, ref);
                            if (id == null) return;
                            await store.addSeries(id, entry);
                            ref.read(collectionsRevisionProvider.notifier).state++;
                            setSheetState(() {});
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('New'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (collections.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No collections yet - tap New to make one.',
                          style: AppText.body(
                            size: 12.5,
                            color: AppColors.text45,
                          ),
                        ),
                      ),
                    for (final c in collections)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(c.name, style: AppText.body(size: 14)),
                        // Entries saved before servers were recorded are a
                        // bare series id - count those too.
                        value: c.seriesIds.contains(entry) ||
                            c.seriesIds.contains(seriesId),
                        onChanged: (checked) async {
                          if (checked == true) {
                            await store.addSeries(c.id, entry);
                          } else {
                            await store.removeSeries(c.id, entry);
                            await store.removeSeries(c.id, seriesId);
                          }
                          ref
                              .read(collectionsRevisionProvider.notifier)
                              .state++;
                          setSheetState(() {});
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final headers = widget.backend.imageHeaders;
    final wide = MediaQuery.of(context).size.width > 700;
    final tasksAsync = ref.watch(downloadQueueProvider);
    final tasks = tasksAsync.valueOrNull ?? const <DownloadTask>[];

    return Scaffold(
      backgroundColor: AppColors.page,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          children: [
            Positioned.fill(child: _content(headers, wide, tasks)),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Center(
                child: ChapterSelectionBar(
                  count: _selected.length,
                  total: _ordered.length,
                  anyDownloaded: _anyDownloaded(_selectedBooks, tasks),
                  onAction: (a) => _runAction(a, _selectedBooks),
                  onSelectAll: () => setState(
                    () => _selected.addAll(_ordered.map((b) => b.id)),
                  ),
                  onClear: () => setState(_selected.clear),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(
    Map<String, String> headers,
    bool wide,
    List<DownloadTask> tasks,
  ) {
    return FutureBuilder<Series>(
      future: _seriesFuture,
      builder: (context, seriesSnapshot) {
        if (seriesSnapshot.hasError) {
          return AppErrorState(
            error: seriesSnapshot.error!,
            onRetry: _reloadSeries,
          );
        }
        if (!seriesSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final series = seriesSnapshot.data!;
        final seriesTasks = tasks
            .where((t) => t.seriesId == widget.seriesId)
            .toList();

        // Built once the books are known, so Read can name the chapter.
        Widget header([String? next]) => _SeriesHeader(
          series: series,
          readLabel: next == null ? 'Read' : 'Read Ch. $next',
          headers: headers,
          downloadedCount: seriesTasks
              .where((t) => t.state == DownloadState.done)
              .length,
          onDownloadAll: () => _downloadSeries(series),
          onRead: () async {
            final books = await _booksFuture;
            if (!context.mounted || books.isEmpty) return;
            final next = books.firstWhere(
              (b) => !b.completed,
              orElse: () => books.first,
            );
            context.push('/read/${Uri.encodeComponent(next.id)}');
          },
          onSaveToCollection: () => _showCollectionPicker(context, series.id),
          onMore: () => _showActions(
            series,
            seriesTasks.where((t) => t.state == DownloadState.done).length,
          ),
        );

        return FutureBuilder<List<Book>>(
          future: _booksFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return CustomScrollView(slivers: [
                if (!wide) SliverToBoxAdapter(child: header()),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: AppErrorState(
                      error: snapshot.error!,
                      onRetry: _reloadBooks,
                    ),
                  ),
                ),
              ]);
            }
            if (!snapshot.hasData) {
              return CustomScrollView(slivers: [
                if (!wide) SliverToBoxAdapter(child: header()),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              ]);
            }
            final books = List<Book>.from(snapshot.data!);
            final upNext = books.isEmpty
                ? null
                : formatChapterNumber(books
                    .firstWhere((b) => !b.completed, orElse: () => books.first)
                    .number);
            final ordered = _newestFirst ? books.reversed.toList() : books;
            _ordered = ordered;

            void onDownloadBook(Book book) => ref
                .read(downloadManagerProvider)
                .enqueueBook(
                  widget.backend,
                  bookId: book.id,
                  seriesId: widget.seriesId,
                  seriesTitle: series.title,
                  title: book.title,
                  totalPages: book.pageCount,
                );

            final chapterSlivers = _chapterSlivers(
              books: ordered,
              headers: headers,
              tasks: tasks,
              onDownloadBook: onDownloadBook,
            );

            if (wide) {
              return Row(
                // Stretch, so the details pane is card-coloured full height.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Prototype "Series on a tablet": the details on card
                  // colour, divided from the reading log by a 3px ink frame.
                  Container(
                    width: 400,
                    color: AppColors.card,
                    child: SingleChildScrollView(child: header(upNext)),
                  ),
                  Container(width: 3, color: AppColors.text),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        // This screen sits outside GlassNavScaffold's shell
                        // (a full-screen sibling route), so it doesn't
                        // inherit the app's shared max-content-width - an
                        // ultrawide monitor would otherwise stretch chapter
                        // rows into unreadably long lines.
                        constraints: const BoxConstraints(maxWidth: 820),
                        child: CustomScrollView(slivers: chapterSlivers),
                      ),
                    ),
                  ),
                ],
              );
            }

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: header(upNext)),
                ...chapterSlivers,
              ],
            );
          },
        );
      },
    );
  }

  List<Widget> _chapterSlivers({
    required List<Book> books,
    required Map<String, String> headers,
    required List<DownloadTask> tasks,
    required ValueChanged<Book> onDownloadBook,
  }) {
    return [
      SliverToBoxAdapter(
        child: _ChaptersHeaderRow(
          newestFirst: _newestFirst,
          onToggleSort: () => setState(() => _newestFirst = !_newestFirst),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverList.builder(
          itemCount: books.length,
          itemBuilder: (context, i) {
            final book = books[i];
            final task = tasks.where((t) => t.bookId == book.id).firstOrNull;
            return _ChapterRow(
              book: book,
              headers: headers,
              task: task,
              selecting: _selected.isNotEmpty,
              selected: _selected.contains(book.id),
              onTap: () => _onTapBook(book),
              onLongPress: () => _onLongPressBook(book),
              onSecondaryTap: (at) => _onSecondaryTap(book, at, tasks),
              onDownload: () => onDownloadBook(book),
              onRename: widget.backend is LocalBackend
                  ? () => _renameBook(book)
                  : null,
            );
          },
        ),
      ),
      // Room for the selection bar to sit below the last row.
      const SliverToBoxAdapter(child: SizedBox(height: 96)),
    ];
  }
}

class _SeriesHeader extends StatelessWidget {
  final Series series;
  final Map<String, String> headers;
  final int downloadedCount;
  final VoidCallback onDownloadAll;
  final VoidCallback onRead;
  final VoidCallback onSaveToCollection;
  final String readLabel;
  final VoidCallback onMore;

  const _SeriesHeader({
    required this.series,
    this.readLabel = 'Read',
    required this.headers,
    required this.downloadedCount,
    required this.onDownloadAll,
    required this.onRead,
    required this.onSaveToCollection,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final progressPct = series.booksCount == 0
        ? 0
        : ((series.booksReadCount / series.booksCount) * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The cover as a backdrop, closed by a 3px ink frame line.
        Container(
          height: 326,
          foregroundDecoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.text, width: 3)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              SeriesCover(imageUrl: series.bannerUrl ?? series.thumbnailUrl, headers: headers, framed: false),
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
                child: _BackButton(onTap: () => context.popOrHome()),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 104,
                      height: 152,
                      child: SeriesCover(imageUrl: series.thumbnailUrl, headers: headers),
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
                          if (series.credits != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              series.credits!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body(
                                size: 13,
                                color: AppColors.text60,
                                weight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          // One mono line instead of badges: source, tags,
                          // and where you stand.
                          Text(
                            [
                              if (series.sourceName != null) series.sourceName!,
                              ...series.tags.take(2),
                              series.isFullyRead ? 'Complete' : 'Reading',
                            ].map((s) => s.toUpperCase()).join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.mono(size: 11, color: AppColors.text60),
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
                  label: readLabel,
                  filled: true,
                  onTap: onRead,
                ),
              ),
              const SizedBox(width: 10),
              _ActionIconButton(
                icon: Icons.download_outlined,
                onTap: onDownloadAll,
              ),
              const SizedBox(width: 10),
              _ActionIconButton(
                icon: Icons.bookmark_border,
                onTap: onSaveToCollection,
              ),
              const SizedBox(width: 10),
              _ActionIconButton(icon: Icons.more_horiz_rounded, onTap: onMore),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          // One mono line and a progress rule, not a row of big numbers.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${series.booksCount} CHAPTERS · ${series.booksUnreadCount} UNREAD · '
                '$downloadedCount ON DEVICE · $progressPct%',
                style: AppText.mono(size: 11, color: AppColors.text60),
              ),
              const SizedBox(height: 8),
              ClipRect(
                child: LinearProgressIndicator(
                  value: progressPct / 100,
                  minHeight: 4,
                  color: AppColors.accent,
                  backgroundColor: AppColors.border,
                  semanticsLabel: 'Read $progressPct%',
                ),
              ),
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
              style: AppText.body(
                size: 13,
                color: AppColors.text60,
                weight: FontWeight.w400,
              ),
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
        // Sits on cover art, so it keeps its scrim on every platform; only
        // the glyph follows the platform.
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            PlatformStyle.isIOS
                ? Icons.arrow_back_ios_new_rounded
                : Icons.arrow_back,
            size: PlatformStyle.isIOS ? 15 : 18,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _ActionButton({
    required this.icon,
    required this.label,
    this.filled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) =>
      InkButton(icon: icon, label: label, filled: filled, onTap: onTap);
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _ActionIconButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) =>
      InkButton(icon: icon, onTap: onTap);
}

class _ChaptersHeaderRow extends StatelessWidget {
  final bool newestFirst;
  final VoidCallback onToggleSort;

  const _ChaptersHeaderRow({
    required this.newestFirst,
    required this.onToggleSort,
  });

  @override
  Widget build(BuildContext context) {
    // "Chapters", the sort as an ink chip, and a 2px ink rule the reading
    // log hangs from.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
      child: Container(
        padding: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.text, width: 2)),
        ),
        child: Row(
          children: [
            Expanded(child: Text('Chapters', style: AppText.heading(size: 20))),
            InkChip(
              label: newestFirst ? 'Newest first' : 'Oldest first',
              icon: Icons.swap_vert_rounded,
              selected: false,
              onTap: onToggleSort,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  final Book book;
  final Map<String, String> headers;
  final DownloadTask? task;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<Offset> onSecondaryTap;
  final VoidCallback onDownload;
  final VoidCallback? onRename;

  const _ChapterRow({
    required this.book,
    required this.headers,
    required this.task,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onSecondaryTap,
    required this.onDownload,
    this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final isInProgress = !book.completed && (book.readProgressPage ?? 0) > 0;
    // Some sources (Suwayomi) don't know a chapter's page count until it has
    // been opened, so a 0 means "unknown", not "zero pages".
    final known = book.pageCount > 0;
    String withPages(String state) =>
        known ? '${book.pageCount} PAGES · $state' : state;
    final meta = book.completed
        ? withPages('READ')
        : isInProgress
        ? (known
              ? 'PAGE ${book.readProgressPage} OF ${book.pageCount}'
              : 'PAGE ${book.readProgressPage}')
        : task?.state == DownloadState.done
        ? withPages('DOWNLOADED')
        : withPages('ON SERVER');

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTapDown: (d) => onSecondaryTap(d.globalPosition),
      hoverColor: AppColors.fillHover,
      child: AnimatedContainer(
        duration: Motion.scaled(context, Motion.fast),
        curve: Motion.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            // The tick slides the row's label over rather than popping in.
            AnimatedContainer(
              duration: Motion.scaled(context, Motion.fast),
              curve: Motion.easeOut,
              width: selecting ? 32 : 0,
              height: 24,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: 32,
                  maxHeight: 24,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 20,
                      color: selected ? AppColors.accent : AppColors.text30,
                    ),
                  ),
                ),
              ),
            ),
            // A reading log: the chapter you are in is violet, read ones
            // step back.
            SizedBox(
              width: 64,
              child: Text(
                'CH ${formatChapterNumber(book.number)}',
                style: AppText.mono(
                    size: 12,
                    color: isInProgress ? AppColors.accentLink : AppColors.text60),
              ),
            ),
            Expanded(
              child: Opacity(
                opacity: book.completed ? 0.62 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(size: 15, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(isInProgress ? 'READING · $meta' : meta,
                        style: AppText.mono(
                            size: 10.5,
                            color: isInProgress ? AppColors.accentLink : AppColors.text60)),
                  ],
                ),
              ),
            ),
            if (onRename != null)
              InkWell(
                onTap: onRename,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.edit_outlined, size: 16, color: AppColors.text30),
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
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.text30,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
