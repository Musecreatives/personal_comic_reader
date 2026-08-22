import 'package:flutter/material.dart';

import '../../../core/backend/reader_backend.dart';
import '../../../core/reader/color_filters.dart';
import '../../../core/reader/page_cache.dart';
import '../../../core/reader/reader_settings.dart';
import '../../../core/reader/spread_logic.dart';
import 'page_image.dart';
import 'zoomable_page.dart';

class DoublePageView extends StatefulWidget {
  final ReaderBackend backend;
  final PageCache pageCache;
  final String bookId;
  final int pageCount;
  final int initialPage;
  final ReaderSettings settings;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onTapCenter;
  final VoidCallback onEndOfBook;

  const DoublePageView({
    super.key,
    required this.backend,
    required this.pageCache,
    required this.bookId,
    required this.pageCount,
    required this.initialPage,
    required this.settings,
    required this.onPageChanged,
    required this.onTapCenter,
    required this.onEndOfBook,
  });

  @override
  State<DoublePageView> createState() => DoublePageViewState();
}

class DoublePageViewState extends State<DoublePageView> {
  late final PageController _controller;
  final Map<int, double> _aspect = {};
  late List<List<int>> _spreads;
  late int _currentSpreadIndex;
  bool _zoomed = false;

  bool _isLandscape(int pageIndex) => (_aspect[pageIndex] ?? 1) > 1.15;

  List<List<int>> _computeSpreads() => buildSpreads(
        pageCount: widget.pageCount,
        coverAlone: widget.settings.doublePageCoverAlone,
        offset: widget.settings.doublePageOffset,
        isLandscape: _isLandscape,
      );

  @override
  void initState() {
    super.initState();
    _spreads = _computeSpreads();
    _currentSpreadIndex =
        _spreads.indexWhere((s) => s.contains(widget.initialPage));
    if (_currentSpreadIndex < 0) _currentSpreadIndex = 0;
    _controller = PageController(initialPage: _currentSpreadIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateAspect(int pageIndex, double ratio) {
    final wasLandscape = _isLandscape(pageIndex);
    _aspect[pageIndex] = ratio;
    if (wasLandscape != _isLandscape(pageIndex)) {
      _rebuildSpreads();
    }
  }

  void _rebuildSpreads() {
    final anchorPage = _spreads[_currentSpreadIndex].first;
    final newSpreads = _computeSpreads();
    final newIndex = newSpreads.indexWhere((s) => s.contains(anchorPage));
    setState(() => _spreads = newSpreads);
    if (newIndex >= 0 && newIndex != _currentSpreadIndex) {
      _currentSpreadIndex = newIndex;
      _controller.jumpToPage(newIndex);
    }
  }

  void jumpTo(int page) {
    final idx = _spreads.indexWhere((s) => s.contains(page));
    if (idx >= 0) _controller.jumpToPage(idx);
  }

  void _goPrevious() {
    if (_currentSpreadIndex > 0) {
      _controller.previousPage(
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _goNext() {
    if (_currentSpreadIndex >= _spreads.length - 1) {
      widget.onEndOfBook();
    } else {
      _controller.nextPage(
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  BoxFit get _fit {
    switch (widget.settings.fit) {
      case PageFit.width:
        return BoxFit.fitWidth;
      case PageFit.height:
        return BoxFit.fitHeight;
      case PageFit.screen:
        return BoxFit.contain;
      case PageFit.original:
        return BoxFit.none;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = widget.settings.direction == ReadingDirection.rtl;
    return PageView.builder(
      controller: _controller,
      reverse: isRtl,
      physics: _zoomed
          ? const NeverScrollableScrollPhysics()
          : const PageScrollPhysics(),
      itemCount: _spreads.length,
      onPageChanged: (i) {
        _currentSpreadIndex = i;
        widget.onPageChanged(_spreads[i].first);
      },
      itemBuilder: (context, index) {
        final spread = _spreads[index];
        final order = spreadDisplayOrder(spread, widget.settings.direction);
        return ZoomablePage(
          tapZonesEnabled: widget.settings.tapZonesEnabled,
          onZoomChanged: (z) => setState(() => _zoomed = z),
          onTapPrevious: isRtl ? _goNext : _goPrevious,
          onTapNext: isRtl ? _goPrevious : _goNext,
          onTapCenter: widget.onTapCenter,
          child: Container(
            color: Color(widget.settings.backgroundColor),
            child: Row(
              children: order
                  .map((pageIndex) => Expanded(
                        child: PageImage(
                          backend: widget.backend,
                          pageCache: widget.pageCache,
                          bookId: widget.bookId,
                          pageIndex: pageIndex,
                          fit: _fit,
                          colorFilter:
                              readerColorFilter(widget.settings.colorFilter),
                          brightness: widget.settings.brightness / 100,
                          upscale: widget.settings.upscale,
                          onAspectRatio: (r) => _updateAspect(pageIndex, r),
                        ),
                      ))
                  .toList(),
            ),
          ),
        );
      },
    );
  }
}
