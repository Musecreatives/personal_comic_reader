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
  double _itemExtent = 600;
  bool _endReported = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scroll.jumpTo(widget.initialPage * _itemExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _onScroll() {
    final index =
        (_scroll.offset / _itemExtent).round().clamp(0, widget.pageCount - 1);
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
    _scroll.jumpTo((page * _itemExtent)
        .clamp(0, _scroll.position.maxScrollExtent.isFinite
            ? _scroll.position.maxScrollExtent
            : page * _itemExtent));
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
    final width = MediaQuery.of(context).size.width;
    _itemExtent = width / 0.7 + widget.settings.pageGap;

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
        itemExtent: _itemExtent,
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
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
