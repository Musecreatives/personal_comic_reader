import 'package:flutter/material.dart';

import '../../../core/backend/reader_backend.dart';
import '../../../core/reader/color_filters.dart';
import '../../../core/reader/page_cache.dart';
import '../../../core/reader/reader_settings.dart';
import 'page_image.dart';
import 'zoomable_page.dart';

class SinglePageView extends StatefulWidget {
  final ReaderBackend backend;
  final PageCache pageCache;
  final String bookId;
  final int pageCount;
  final int initialPage;
  final ReaderSettings settings;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onTapCenter;
  final VoidCallback onEndOfBook;

  const SinglePageView({
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
  State<SinglePageView> createState() => SinglePageViewState();
}

class SinglePageViewState extends State<SinglePageView> {
  late final PageController _controller;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initialPage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goPrevious() {
    if (_controller.page != null && _controller.page! > 0) {
      _controller.previousPage(
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _goNext() {
    final current = _controller.page?.round() ?? widget.initialPage;
    if (current >= widget.pageCount - 1) {
      widget.onEndOfBook();
    } else {
      _controller.nextPage(
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void jumpTo(int page) => _controller.jumpToPage(page);

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
      itemCount: widget.pageCount,
      onPageChanged: widget.onPageChanged,
      itemBuilder: (context, index) {
        return ZoomablePage(
          tapZonesEnabled: widget.settings.tapZonesEnabled,
          onZoomChanged: (z) => setState(() => _zoomed = z),
          onTapPrevious: isRtl ? _goNext : _goPrevious,
          onTapNext: isRtl ? _goPrevious : _goNext,
          onTapCenter: widget.onTapCenter,
          child: Container(
            color: Color(widget.settings.backgroundColor),
            child: Center(
              child: PageImage(
                backend: widget.backend,
                pageCache: widget.pageCache,
                bookId: widget.bookId,
                pageIndex: index,
                fit: _fit,
                colorFilter: readerColorFilter(widget.settings.colorFilter),
                brightness: widget.settings.brightness / 100,
                upscale: widget.settings.upscale,
              ),
            ),
          ),
        );
      },
    );
  }
}
