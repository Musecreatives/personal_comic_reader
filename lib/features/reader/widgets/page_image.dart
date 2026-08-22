import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/backend/reader_backend.dart';
import '../../../core/reader/page_cache.dart';

/// Loads and renders a single page's bytes, with a retry button on failure
/// and an aspect-ratio callback used by double-page mode to detect
/// landscape pages.
class PageImage extends StatefulWidget {
  final ReaderBackend backend;
  final PageCache pageCache;
  final String bookId;
  final int pageIndex;
  final BoxFit fit;
  final ColorFilter? colorFilter;
  final double brightness;
  final bool upscale;
  final ValueChanged<double>? onAspectRatio;

  const PageImage({
    super.key,
    required this.backend,
    required this.pageCache,
    required this.bookId,
    required this.pageIndex,
    required this.fit,
    this.colorFilter,
    this.brightness = 1,
    this.upscale = false,
    this.onAspectRatio,
  });

  @override
  State<PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<PageImage> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PageImage old) {
    super.didUpdateWidget(old);
    if (old.pageIndex != widget.pageIndex || old.bookId != widget.bookId) {
      _load();
    }
  }

  void _load() {
    _future = widget.pageCache
        .getPage(widget.backend, widget.bookId, widget.pageIndex);
  }

  void _retry() {
    setState(_load);
  }

  Future<void> _reportAspectRatio(Uint8List bytes) async {
    if (widget.onAspectRatio == null) return;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final ratio = frame.image.width / frame.image.height;
      frame.image.dispose();
      widget.onAspectRatio!(ratio);
    } catch (_) {
      // Best-effort only; landscape detection just won't apply.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image_outlined, size: 40),
                const SizedBox(height: 12),
                const Text('Failed to load page'),
                const SizedBox(height: 12),
                FilledButton(onPressed: _retry, child: const Text('Retry')),
              ],
            ),
          );
        }

        final bytes = snapshot.data!;
        _reportAspectRatio(bytes);

        Widget image = Image.memory(
          bytes,
          fit: widget.fit,
          filterQuality: widget.upscale ? FilterQuality.high : FilterQuality.low,
        );

        if (widget.colorFilter != null) {
          image = ColorFiltered(colorFilter: widget.colorFilter!, child: image);
        }

        if (widget.brightness < 1) {
          image = Stack(
            fit: StackFit.passthrough,
            children: [
              image,
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black
                        .withValues(alpha: (1 - widget.brightness).clamp(0, 1)),
                  ),
                ),
              ),
            ],
          );
        }

        return image;
      },
    );
  }
}
