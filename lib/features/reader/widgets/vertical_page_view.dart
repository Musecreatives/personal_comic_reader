import 'package:flutter/material.dart';

import '../../../core/backend/reader_backend.dart';
import '../../../core/reader/color_filters.dart';
import '../../../core/reader/page_cache.dart';
import '../../../core/reader/reader_settings.dart';
import 'page_image.dart';

class VerticalPageView extends StatefulWidget {
  final ReaderBackend backend;
  final PageCache pageCache;
  final String bookId;
  final int pageCount;
  final int initialPage;
  final ReaderSettings settings;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onTapCenter;
  final VoidCallback onEndOfBook;

  const VerticalPageView({
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
  State<VerticalPageView> createState() => VerticalPageViewState();
}

class VerticalPageViewState extends State<VerticalPageView> {
  final ScrollController _scroll = ScrollController();
  final TransformationController _transform = TransformationController();
  bool _zoomed = false;
  int _lastReported = -1;
  bool _endReported = false;
  double _width = 400;

  // Each page's width / height once its header is read. Until then a page
  // is assumed to be a normal manga page; strips (800x16000 on some
  // sources) get their real height so they read at full width.
  static const _defaultRatio = 0.7;
  final Map<int, double> _ratios = {};

  double _extent(int index) =>
      _width / (_ratios[index] ?? _defaultRatio) + widget.settings.pageGap;

  double _offsetOf(int page) {
    var offset = 0.0;
    for (var i = 0; i < page; i++) {
      offset += _extent(i);
    }
    return offset;
  }

  int _pageAt(double offset) {
    var top = 0.0;
    for (var i = 0; i < widget.pageCount; i++) {
      final extent = _extent(i);
      // The page at the top of the screen, matching where jumpTo lands.
      if (top + extent > offset + 1) return i;
      top += extent;
    }
    return widget.pageCount - 1;
  }

  void _onAspectRatio(int index, double ratio) {
    if (_ratios[index] == ratio) return;
    final before = _extent(index);
    setState(() => _ratios[index] = ratio);
    // A page above the screen changing height would shove what's being
    // read; scroll by the same amount so it stays put.
    if (_scroll.hasClients && _offsetOf(index) < _scroll.offset) {
      final delta = _extent(index) - before;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.offset + delta);
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scroll.jumpTo(_offsetOf(widget.initialPage));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _onScroll() {
    final index = _pageAt(_scroll.offset);
    if (index != _lastReported) {
      _lastReported = index;
      widget.onPageChanged(index);
    }
    if (!_endReported &&
        _scroll.position.maxScrollExtent > 0 &&
        _scroll.offset >= _scroll.position.maxScrollExtent - 20) {
      _endReported = true;
      widget.onEndOfBook();
    }
  }

  void jumpTo(int page) {
    final offset = _offsetOf(page);
    _scroll.jumpTo(offset.clamp(
        0,
        _scroll.position.maxScrollExtent.isFinite
            ? _scroll.position.maxScrollExtent
            : offset));
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
    _width = MediaQuery.of(context).size.width;

    return InteractiveViewer(
      transformationController: _transform,
      minScale: 1,
      maxScale: 4,
      panEnabled: _zoomed,
      onInteractionEnd: (_) {
        setState(() => _zoomed = _transform.value.getMaxScaleOnAxis() > 1.01);
      },
      child: ListView.builder(
        controller: _scroll,
        physics: _zoomed
            ? const NeverScrollableScrollPhysics()
            : const ClampingScrollPhysics(),
        itemExtentBuilder: (index, _) => _extent(index),
        itemCount: widget.pageCount,
        itemBuilder: (context, index) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTapCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.settings.pageGap),
              child: Container(
                color: Color(widget.settings.backgroundColor),
                child: PageImage(
                  backend: widget.backend,
                  pageCache: widget.pageCache,
                  bookId: widget.bookId,
                  pageIndex: index,
                  fit: _fit,
                  colorFilter: readerColorFilter(widget.settings.colorFilter),
                  brightness: widget.settings.brightness / 100,
                  upscale: widget.settings.upscale,
                  onAspectRatio: (r) => _onAspectRatio(index, r),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
