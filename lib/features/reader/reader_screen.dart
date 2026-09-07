import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
import '../../core/history/history_entry.dart';
import '../../core/history/history_store.dart';
import '../../core/reader/page_cache.dart';
import '../../core/reader/progress_sync.dart';
import '../../core/reader/reader_settings.dart';
import '../../core/reader/reader_settings_store.dart';
import '../../core/panels/panel_detector.dart';
import '../../core/stats/reading_stats_store.dart';
import '../shared/error_state.dart';
import 'widgets/double_page_view.dart';
import 'widgets/panel_zoom_view.dart';
import 'widgets/reader_overlay.dart';
import 'widgets/reader_settings_sheet.dart';
import 'widgets/single_page_view.dart';
import 'widgets/vertical_page_view.dart';

class ReaderScreen extends ConsumerWidget {
  final String bookId;
  final int? initialPage;

  const ReaderScreen({super.key, required this.bookId, this.initialPage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backendAsync = ref.watch(activeBackendProvider);
    return backendAsync.when(
      loading: () => const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        backgroundColor: Colors.black,
        body: AppErrorState(
          error: e,
          onRetry: () => ref.invalidate(activeBackendProvider),
        ),
      ),
      data: (backend) {
        if (backend == null) {
          return const Scaffold(
              backgroundColor: Colors.black, body: Center(child: Text('No server')));
        }
        return _ReaderLoader(backend: backend, bookId: bookId, initialPage: initialPage);
      },
    );
  }
}

class _ReaderLoader extends ConsumerStatefulWidget {
  final ReaderBackend backend;
  final String bookId;
  final int? initialPage;

  const _ReaderLoader({required this.backend, required this.bookId, this.initialPage});

  @override
  ConsumerState<_ReaderLoader> createState() => _ReaderLoaderState();
}

class _ReaderLoaderState extends ConsumerState<_ReaderLoader> {
  late Future<(Book, List<Book>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(Book, List<Book>)> _load() async {
    final book = await widget.backend.getBook(widget.bookId);
    final books = await widget.backend.listBooks(book.seriesId);
    return (book, books);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(Book, List<Book>)>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError) {
            return Scaffold(
              backgroundColor: Colors.black,
              body: AppErrorState(
                error: snapshot.error!,
                onRetry: () => setState(() => _future = _load()),
              ),
            );
          }
          return const Scaffold(
              backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
        }
        final (book, seriesBooks) = snapshot.data!;
        return _ReaderBody(
          backend: widget.backend,
          book: book,
          seriesBooks: seriesBooks,
          initialPage: widget.initialPage,
        );
      },
    );
  }
}

class _ReaderBody extends ConsumerStatefulWidget {
  final ReaderBackend backend;
  final Book book;
  final List<Book> seriesBooks;
  final int? initialPage;

  const _ReaderBody({
    required this.backend,
    required this.book,
    required this.seriesBooks,
    this.initialPage,
  });

  @override
  ConsumerState<_ReaderBody> createState() => _ReaderBodyState();
}

class _ReaderBodyState extends ConsumerState<_ReaderBody> with WidgetsBindingObserver {
  final _singleKey = GlobalKey<SinglePageViewState>();
  final _doubleKey = GlobalKey<DoublePageViewState>();
  final _verticalKey = GlobalKey<VerticalPageViewState>();

  late ReaderSettings _settings;
  late bool _remember;
  late int _currentPage;
  bool _overlayVisible = false;
  bool _showEndCard = false;

  // Experimental smart panel view (single-page mode only).
  bool _panelModeActive = false;
  bool _panelLoading = false;
  Uint8List? _panelPageBytes;
  List<PanelRect>? _panelRects;

  final Set<int> _seenPages = {};
  late DateTime _sessionStart;

  ReaderSettingsStore get _settingsStore => ref.read(readerSettingsStoreProvider);
  ProgressSync get _progressSync => ref.read(progressSyncProvider);
  PageCache get _pageCache => ref.read(pageCacheProvider);
  ReadingStatsStore get _statsStore => ref.read(readingStatsStoreProvider);
  HistoryStore get _historyStore => ref.read(historyStoreProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settings = _settingsStore.effective(widget.book.seriesId);
    _remember = _settingsStore.hasOverride(widget.book.seriesId);
    _currentPage = widget.initialPage ?? widget.book.readProgressPage ?? 0;
    if (_currentPage < 0 || _currentPage >= widget.book.pageCount) {
      _currentPage = 0;
    }
    _sessionStart = DateTime.now();
    _seenPages.add(_currentPage);
    _applyWakelock();
    _pageCache.prefetch(widget.backend, widget.book.id, _currentPage + 1,
        widget.book.pageCount);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _checkpointSession();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Progress/stats/history used to only get written in dispose(), which
    // assumes a clean Flutter widget unmount - but a backgrounded mobile
    // PWA is routinely suspended or killed by the OS without ever tearing
    // the widget tree down, silently losing the whole session. Checkpoint
    // on every pause/inactive/detach too, not just a real close, so
    // nothing depends on the app being allowed to exit gracefully.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _checkpointSession();
    }
  }

  /// Writes progress/stats/history for however much of the session has
  /// happened since the last checkpoint, then resets the session clock so
  /// a later checkpoint (dispose, or another backgrounding) only counts
  /// the time since *this* checkpoint - otherwise calling this more than
  /// once per session would double-count reading time.
  void _checkpointSession() {
    final completed = _currentPage >= widget.book.pageCount - 1;
    _progressSync.sendNow(
      widget.backend,
      widget.book.id,
      page: _currentPage,
      completed: completed,
    );
    final elapsed = DateTime.now().difference(_sessionStart).inSeconds;
    if (elapsed > 0) {
      _statsStore.recordSeconds(elapsed);
      _sessionStart = DateTime.now();
    }
    // Only log a session that actually turned a page - opening a book and
    // immediately backing out shouldn't clutter history.
    if (_seenPages.length > 1 || completed) {
      _historyStore.record(HistoryEntry(
        bookId: widget.book.id,
        seriesId: widget.book.seriesId,
        bookTitle: widget.book.title,
        bookNumber: widget.book.number,
        pageCount: widget.book.pageCount,
        lastPage: _currentPage,
        completed: completed,
        timestamp: DateTime.now(),
      ));
      ref.read(historyRevisionProvider.notifier).state++;
    }
  }

  void _applyWakelock() {
    if (_settings.keepScreenOn) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
    final completed = page >= widget.book.pageCount - 1;
    _progressSync.scheduleUpdate(widget.backend, widget.book.id,
        page: page, completed: completed);
    _pageCache.prefetch(
        widget.backend, widget.book.id, page + 1, widget.book.pageCount);
    if (_seenPages.add(page)) {
      _statsStore.recordPages(1);
    }
  }

  void _toggleOverlay() => setState(() => _overlayVisible = !_overlayVisible);

  Future<void> _togglePanelMode() async {
    if (_panelModeActive) {
      setState(() => _panelModeActive = false);
      return;
    }
    if (_panelLoading) return;
    setState(() => _panelLoading = true);
    try {
      final bytes =
          await _pageCache.getPage(widget.backend, widget.book.id, _currentPage);
      final panels = await detectPanels(bytes,
          rtl: _settings.direction == ReadingDirection.rtl);
      if (!mounted) return;
      setState(() {
        _panelPageBytes = bytes;
        _panelRects = panels;
        _panelModeActive = true;
        _panelLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _panelLoading = false);
    }
  }

  void _seek(int page) {
    switch (_settings.mode) {
      case ReaderMode.single:
        _singleKey.currentState?.jumpTo(page);
      case ReaderMode.double:
        _doubleKey.currentState?.jumpTo(page);
      case ReaderMode.verticalContinuous:
        _verticalKey.currentState?.jumpTo(page);
    }
    _onPageChanged(page);
  }

  void _updateSettings(ReaderSettings settings) {
    setState(() => _settings = settings);
    _applyWakelock();
    _persistSettings();
  }

  void _persistSettings() {
    if (_remember) {
      _settingsStore.setForSeries(widget.book.seriesId, _settings);
    } else {
      _settingsStore.setGlobal(_settings);
    }
  }

  void _onRememberChanged(bool remember) {
    setState(() => _remember = remember);
    if (remember) {
      _settingsStore.setForSeries(widget.book.seriesId, _settings);
    } else {
      _settingsStore.clearForSeries(widget.book.seriesId);
      _settingsStore.setGlobal(_settings);
    }
  }

  void _cycleMode() {
    final modes = ReaderMode.values;
    final next = modes[(modes.indexOf(_settings.mode) + 1) % modes.length];
    _updateSettings(_settings.copyWith(mode: next));
  }

  void _toggleDirection() {
    _updateSettings(_settings.copyWith(
      direction: _settings.direction == ReadingDirection.ltr
          ? ReadingDirection.rtl
          : ReadingDirection.ltr,
    ));
  }

  void _openSettingsSheet() {
    ReaderSettingsSheet.show(
      context,
      settings: _settings,
      rememberForSeries: _remember,
      onChanged: _updateSettings,
      onRememberChanged: _onRememberChanged,
    );
  }

  Book? get _nextBook {
    final i = widget.seriesBooks.indexWhere((b) => b.id == widget.book.id);
    if (i < 0 || i + 1 >= widget.seriesBooks.length) return null;
    return widget.seriesBooks[i + 1];
  }

  Book? get _previousBook {
    final i = widget.seriesBooks.indexWhere((b) => b.id == widget.book.id);
    if (i <= 0) return null;
    return widget.seriesBooks[i - 1];
  }

  void _goToBook(String bookId) {
    context.pushReplacement('/read/${Uri.encodeComponent(bookId)}');
  }

  Future<void> _markBooksRead(Iterable<Book> books) async {
    for (final b in books) {
      await widget.backend.updateProgress(b.id, page: b.pageCount - 1, completed: true);
    }
  }

  Future<void> _downloadBooks(Iterable<Book> books) async {
    final manager = ref.read(downloadManagerProvider);
    await manager.enqueueBooks(
      widget.backend,
      books.toList(),
      widget.book.seriesId,
      widget.book.title,
    );
  }

  Future<void> _deleteBooks(Iterable<Book> books) async {
    final manager = ref.read(downloadManagerProvider);
    for (final b in books) {
      await manager.cancel(b.id);
    }
  }

  void _openChapterPicker() {
    var selectMode = false;
    final selected = <String>{};

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> runBulk(Future<void> Function(Iterable<Book>) action, String doneMessage) async {
            final books = widget.seriesBooks.where((b) => selected.contains(b.id));
            Navigator.pop(sheetContext);
            await action(books);
            if (mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(doneMessage)));
            }
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.75),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            selectMode ? '${selected.length} selected' : widget.book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setSheetState(() {
                            selectMode = !selectMode;
                            selected.clear();
                          }),
                          child: Text(
                            selectMode ? 'Cancel' : 'Select',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: widget.seriesBooks.length,
                      itemBuilder: (context, i) {
                        final b = widget.seriesBooks[i];
                        final current = b.id == widget.book.id;
                        final read = b.completed && !current;
                        final isSelected = selected.contains(b.id);
                        return ListTile(
                          selected: current || isSelected,
                          selectedTileColor: Colors.white.withValues(alpha: 0.06),
                          leading: selectMode
                              ? Checkbox(
                                  value: isSelected,
                                  onChanged: (_) => setSheetState(() {
                                    if (isSelected) {
                                      selected.remove(b.id);
                                    } else {
                                      selected.add(b.id);
                                    }
                                  }),
                                )
                              : current
                                  ? const Icon(Icons.play_arrow, color: Colors.white)
                                  : read
                                      ? const Icon(Icons.check_circle, color: Colors.white38, size: 20)
                                      : const Icon(Icons.circle_outlined, color: Colors.white24, size: 18),
                          title: Text(
                            b.title,
                            style: TextStyle(
                              color: current
                                  ? Colors.white
                                  : read
                                      ? Colors.white38
                                      : Colors.white70,
                            ),
                          ),
                          subtitle:
                              Text('Ch. ${b.number}', style: const TextStyle(color: Colors.white38)),
                          onTap: () {
                            if (selectMode) {
                              setSheetState(() {
                                if (isSelected) {
                                  selected.remove(b.id);
                                } else {
                                  selected.add(b.id);
                                }
                              });
                              return;
                            }
                            Navigator.pop(sheetContext);
                            if (!current) _goToBook(b.id);
                          },
                        );
                      },
                    ),
                  ),
                  if (selectMode)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton.icon(
                              onPressed: selected.isEmpty
                                  ? null
                                  : () => runBulk(_markBooksRead, 'Marked as read'),
                              icon: const Icon(Icons.check, color: Colors.white70, size: 18),
                              label: const Text('Mark read', style: TextStyle(color: Colors.white70)),
                            ),
                          ),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: selected.isEmpty
                                  ? null
                                  : () => runBulk(_downloadBooks, 'Queued for download'),
                              icon: const Icon(Icons.download_outlined, color: Colors.white70, size: 18),
                              label: const Text('Download', style: TextStyle(color: Colors.white70)),
                            ),
                          ),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: selected.isEmpty
                                  ? null
                                  : () => runBulk(_deleteBooks, 'Deleted downloads'),
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                              label: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _onEndOfBook() {
    if (_showEndCard) return;
    _progressSync.sendNow(widget.backend, widget.book.id,
        page: widget.book.pageCount - 1, completed: true);
    final next = _nextBook;
    if (next != null) {
      // Seamless chapter-to-chapter continuation - go straight into the
      // next chapter rather than stopping on an end card, since there's
      // somewhere real to go.
      _goToBook(next.id);
      return;
    }
    setState(() => _showEndCard = true);
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final isRtl = _settings.direction == ReadingDirection.rtl;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      isRtl ? _stepBackward() : _stepForward();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      isRtl ? _stepForward() : _stepBackward();
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      context.pop();
    }
  }

  void _stepForward() {
    if (_currentPage >= widget.book.pageCount - 1) {
      _onEndOfBook();
      return;
    }
    _seek(_currentPage + 1);
  }

  void _stepBackward() {
    if (_currentPage <= 0) {
      final previous = _previousBook;
      if (previous != null) _goToBook(previous.id);
      return;
    }
    _seek(_currentPage - 1);
  }

  Widget _buildPager() {
    switch (_settings.mode) {
      case ReaderMode.single:
        return SinglePageView(
          key: _singleKey,
          backend: widget.backend,
          pageCache: _pageCache,
          bookId: widget.book.id,
          pageCount: widget.book.pageCount,
          initialPage: _currentPage,
          settings: _settings,
          onPageChanged: _onPageChanged,
          onTapCenter: _toggleOverlay,
          onEndOfBook: _onEndOfBook,
        );
      case ReaderMode.double:
        return DoublePageView(
          key: _doubleKey,
          backend: widget.backend,
          pageCache: _pageCache,
          bookId: widget.book.id,
          pageCount: widget.book.pageCount,
          initialPage: _currentPage,
          settings: _settings,
          onPageChanged: _onPageChanged,
          onTapCenter: _toggleOverlay,
          onEndOfBook: _onEndOfBook,
        );
      case ReaderMode.verticalContinuous:
        return VerticalPageView(
          key: _verticalKey,
          backend: widget.backend,
          pageCache: _pageCache,
          bookId: widget.book.id,
          pageCount: widget.book.pageCount,
          initialPage: _currentPage,
          settings: _settings,
          onPageChanged: _onPageChanged,
          onTapCenter: _toggleOverlay,
          onEndOfBook: _onEndOfBook,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..canRequestFocus = true,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: Color(_settings.backgroundColor),
        body: Stack(
          children: [
            Positioned.fill(child: _buildPager()),
            ReaderOverlay(
              visible: _overlayVisible,
              title: widget.book.title,
              subtitle: 'Vol/Ch ${widget.book.number}',
              currentPage: _currentPage,
              pageCount: widget.book.pageCount,
              settings: _settings,
              onSeek: _seek,
              onClose: () => context.pop(),
              onOpenSettings: _openSettingsSheet,
              onToggleDirection: _toggleDirection,
              onCycleMode: _cycleMode,
              onOpenChapters: _openChapterPicker,
              onTogglePanelMode:
                  _settings.mode == ReaderMode.single ? _togglePanelMode : null,
            ),
            if (_panelModeActive && _panelRects != null && _panelPageBytes != null)
              Positioned.fill(
                child: PanelZoomView(
                  imageBytes: _panelPageBytes!,
                  panels: _panelRects!,
                  onExhausted: () => setState(() => _panelModeActive = false),
                  onExit: () => setState(() => _panelModeActive = false),
                ),
              ),
            if (_showEndCard) _EndOfBookCard(
              nextBook: _nextBook,
              onNext: (id) {
                setState(() => _showEndCard = false);
                context.pushReplacement('/read/${Uri.encodeComponent(id)}');
              },
              onBackToSeries: () => context.go('/series/${Uri.encodeComponent(widget.book.seriesId)}'),
              onDismiss: () => setState(() => _showEndCard = false),
            ),
          ],
        ),
      ),
    );
  }
}

class _EndOfBookCard extends StatelessWidget {
  final Book? nextBook;
  final ValueChanged<String> onNext;
  final VoidCallback onBackToSeries;
  final VoidCallback onDismiss;

  const _EndOfBookCard({
    required this.nextBook,
    required this.onNext,
    required this.onBackToSeries,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Card(
        margin: const EdgeInsets.all(32),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 40),
              const SizedBox(height: 12),
              Text('Finished this book',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              if (nextBook != null) ...[
                Text('Next: ${nextBook!.title}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => onNext(nextBook!.id),
                  child: const Text('Continue to next'),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton(
                onPressed: onBackToSeries,
                child: const Text('Back to series'),
              ),
              TextButton(onPressed: onDismiss, child: const Text('Keep reading')),
            ],
          ),
        ),
      ),
    );
  }
}
