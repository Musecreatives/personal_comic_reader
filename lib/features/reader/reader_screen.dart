import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
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

class _ReaderBodyState extends ConsumerState<_ReaderBody> {
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
  late final DateTime _sessionStart;

  ReaderSettingsStore get _settingsStore => ref.read(readerSettingsStoreProvider);
  ProgressSync get _progressSync => ref.read(progressSyncProvider);
  PageCache get _pageCache => ref.read(pageCacheProvider);
  ReadingStatsStore get _statsStore => ref.read(readingStatsStoreProvider);

  @override
  void initState() {
    super.initState();
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
    WakelockPlus.disable();
    _progressSync.sendNow(
      widget.backend,
      widget.book.id,
      page: _currentPage,
      completed: _currentPage >= widget.book.pageCount - 1,
    );
    final elapsed = DateTime.now().difference(_sessionStart).inSeconds;
    _statsStore.recordSeconds(elapsed);
    super.dispose();
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

  void _onEndOfBook() {
    if (_showEndCard) return;
    _progressSync.sendNow(widget.backend, widget.book.id,
        page: widget.book.pageCount - 1, completed: true);
    setState(() => _showEndCard = true);
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final isRtl = _settings.direction == ReadingDirection.rtl;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      isRtl ? _seek((_currentPage - 1).clamp(0, widget.book.pageCount - 1))
          : _seek((_currentPage + 1).clamp(0, widget.book.pageCount - 1));
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      isRtl ? _seek((_currentPage + 1).clamp(0, widget.book.pageCount - 1))
          : _seek((_currentPage - 1).clamp(0, widget.book.pageCount - 1));
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      context.pop();
    }
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
