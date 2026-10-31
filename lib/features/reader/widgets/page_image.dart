import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/backend/reader_backend.dart';
import '../../../core/reader/page_cache.dart';

/// Loads and renders a single page's bytes, with a retry button on failure
/// and an aspect-ratio callback (double-page mode uses it to spot landscape
/// pages, webtoon mode to size each page).
///
/// Some sources (Asura Scans, for one) serve a chapter as a few 800x16000
/// strips. Fitted to the screen those shrink to a sliver, so with
/// [scrollTall] a page taller than [tallRatio] fills the width and scrolls.
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
  final bool scrollTall;

  /// Width / height below which a page counts as a strip: 2.5x taller than
  /// wide, where a normal manga page is about 1.4x.
  static const tallRatio = 0.4;

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
    this.scrollTall = false,
  });

  @override
  State<PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<PageImage> {
  late Future<Uint8List> _future;
  double? _ratio;

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
    _ratio = null;
    _future = widget.pageCache
        .getPage(widget.backend, widget.bookId, widget.pageIndex)
        .then((bytes) async {
      await _readAspectRatio(bytes);
      return bytes;
    });
  }

  void _retry() {
    setState(_load);
  }

  /// Reads the size from the image header without decoding the pixels: a
  /// full decode of a 16000px strip is ~50 MB.
  Future<void> _readAspectRatio(Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      _ratio = descriptor.width / descriptor.height;
      descriptor.dispose();
      buffer.dispose();
      if (mounted) widget.onAspectRatio?.call(_ratio!);
    } catch (_) {
      // Best-effort only; the page just keeps the default layout.
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
        final strip = widget.scrollTall &&
            _ratio != null &&
            _ratio! < PageImage.tallRatio;

        Widget image = Image.memory(
          bytes,
          fit: strip ? BoxFit.fitWidth : widget.fit,
          width: strip ? double.infinity : null,
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

        return strip ? SingleChildScrollView(child: image) : image;
      },
    );
  }
}
