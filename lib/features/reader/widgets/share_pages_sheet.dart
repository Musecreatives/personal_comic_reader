import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/design_tokens.dart';
import '../../../backends/suwayomi/suwayomi_backend.dart';
import '../../../core/backend/models.dart';
import '../../../core/backend/reader_backend.dart';
import '../../../core/panels/panel_detector.dart';
import '../../../core/reader/page_cache.dart';
import '../../../core/share/page_share.dart';
import '../../home/home_feed.dart' show formatChapterNumber;
import '../../shared/app_sheet.dart';
import '../../shared/ink_chip.dart';

/// The reader as it's drawn under [key]'s [RepaintBoundary], as PNG, at
/// most 2560 px on its long side so chats take it. Null if it can't be read.
Future<Uint8List?> captureView(GlobalKey key) async {
  final context = key.currentContext;
  final box = context?.findRenderObject();
  if (context == null || box is! RenderRepaintBoundary || !box.hasSize) {
    return null;
  }
  try {
    final dpr = View.of(context).devicePixelRatio;
    final image = await box.toImage(
      pixelRatio: math.min(dpr, 2560 / box.size.longestSide),
    );
    try {
      return await _png(image);
    } finally {
      image.dispose();
    }
  } catch (_) {
    return null;
  }
}

/// Share to a chat with where it's from, or save to Photos. [screen] (what
/// the reader showed, see [captureView]) starts ticked; tick pages from the
/// chapter to add them. [panel] is set in panel mode, to save just that one.
Future<void> showSharePagesSheet(
  BuildContext context, {
  required ReaderBackend backend,
  required PageCache pageCache,
  required Book book,
  required Book main,
  required int currentPage,
  Uint8List? screen,
  ({Uint8List page, PanelRect rect})? panel,
}) {
  return showAppSheet<void>(
    context: context,
    grabber: true,
    isScrollControlled: true,
    builder: (_) => _SharePagesSheet(
      backend: backend,
      pageCache: pageCache,
      book: book,
      main: main,
      currentPage: currentPage,
      screen: screen,
      panel: panel,
    ),
  );
}

class _SharePagesSheet extends StatefulWidget {
  final ReaderBackend backend;
  final PageCache pageCache;
  final Book book;
  final Book main;
  final int currentPage;
  final Uint8List? screen;
  final ({Uint8List page, PanelRect rect})? panel;

  const _SharePagesSheet({
    required this.backend,
    required this.pageCache,
    required this.book,
    required this.main,
    required this.currentPage,
    this.screen,
    this.panel,
  });

  @override
  State<_SharePagesSheet> createState() => _SharePagesSheetState();
}

class _SharePagesSheetState extends State<_SharePagesSheet> {
  /// In [_picked], what the reader showed; page indices are 0 and up.
  static const _onScreen = -1;

  late final bool _hasScreen = widget.screen != null;
  late final Set<int> _picked = {_hasScreen ? _onScreen : widget.currentPage};
  final _pages = <int, Future<Uint8List>>{};
  final _shareButton = GlobalKey();
  late final ScrollController _strip = ScrollController(
    // Open on the screen tile, or with the current page in view
    // (thumbnails are 104 wide).
    initialScrollOffset: _hasScreen
        ? 0
        : (widget.currentPage * 112.0 - 120).clamp(0, double.infinity),
  );
  late final Future<String> _caption = _buildCaption();
  bool _busy = false;

  Future<Uint8List> _page(int i) => _pages[i] ??= i == _onScreen
      ? Future.value(widget.screen!)
      : widget.pageCache.getPage(widget.backend, widget.book.id, i);

  /// Page numbers for the caption; the screen counts as the current page.
  List<int> get _captionPages =>
      {for (final i in _picked) i == _onScreen ? widget.currentPage : i}
          .toList();

  Future<String> _buildCaption() async {
    Series? series;
    ({String? chapter, String? series})? links;
    try {
      series = await widget.backend.getSeries(widget.main.seriesId);
    } catch (_) {}
    if (widget.backend case final SuwayomiBackend suwayomi) {
      try {
        links = await suwayomi.sourceLinks(widget.book.id);
      } catch (_) {}
    }
    return shareCaption(
      title: series?.title ?? widget.main.title,
      chapter: 'Ch. ${formatChapterNumber(widget.main.number)}',
      source: series?.sourceName,
      pages: _captionPages,
      sourceLink: links?.chapter ?? links?.series,
      appLink: appLinkForSeries(widget.main.seriesId),
    );
  }

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<int> get _sorted => _picked.toList()..sort();

  String _fileName(String part, String ext) {
    final slug = widget.main.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return '$slug-ch${formatChapterNumber(widget.main.number)}-$part.$ext';
  }

  /// Everything ticked, in order, ready for a chat or Photos: the screen,
  /// then each page, webtoon strips cut into screen-sized pieces.
  Future<List<XFile>> _outgoing() async {
    final files = <XFile>[];
    for (final i in _sorted) {
      final page = 'p${(i == _onScreen ? widget.currentPage : i) + 1}';
      final pieces = i == _onScreen
          ? [widget.screen!]
          : await _pieces(await _page(i));
      for (final (k, piece) in pieces.indexed) {
        final (bytes, ext, mime) = await _shareable(piece);
        final part = i == _onScreen
            ? '$page-screen'
            : pieces.length > 1 ? '$page-${k + 1}' : page;
        files.add(XFile.fromData(bytes, name: _fileName(part, ext), mimeType: mime));
      }
    }
    return files;
  }

  Future<void> _share() => _run(() async {
    final files = await _outgoing();
    // Rebuilt so the page list in the caption matches what's ticked.
    final caption = await _buildCaption();
    // Some chats drop the text when several pictures go together; it's on
    // the clipboard to paste.
    await Clipboard.setData(ClipboardData(text: caption));
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // WhatsApp's iOS share extension won't send pictures that come with any
    // text, a subject included, so on iOS the pictures go alone, as from
    // Photos, and the caption goes by clipboard. The device's OS, not
    // PlatformStyle: a forced Android look on an iPhone still has this.
    final pasteCaption = defaultTargetPlatform == TargetPlatform.iOS;
    final box = _shareButton.currentContext?.findRenderObject() as RenderBox?;
    final result = await SharePlus.instance.share(
      ShareParams(
        files: files,
        text: pasteCaption ? null : caption,
        subject: pasteCaption ? null : caption.split('\n').first,
        // iPad anchors the share popover to the button.
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
    if (result.status == ShareResultStatus.success && mounted) {
      Navigator.of(context).pop();
      if (pasteCaption) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Caption and links copied. Paste them in the chat.'),
        ));
      }
    }
  });

  /// [images] runs inside the busy state, so slow cutting can't be tapped twice.
  Future<void> _save(Future<List<Uint8List>> Function() images, String what) =>
      _run(() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await Gal.hasAccess(toAlbum: true) &&
          !await Gal.requestAccess(toAlbum: true)) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Allow Photos access in Settings to save pages'),
        ));
        return;
      }
      for (final bytes in await images()) {
        await Gal.putImageBytes(bytes, album: 'Shaddai Reader');
      }
      messenger.showSnackBar(SnackBar(content: Text('$what saved to Photos')));
      if (mounted) Navigator.of(context).pop();
    } on GalException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text("Couldn't save: ${e.type.message}"),
      ));
    }
  });

  Future<void> _savePages() => _save(
        () async => [for (final f in await _outgoing()) await f.readAsBytes()],
        _picked.length == 1 ? 'Page' : '${_picked.length} pages',
      );

  Future<void> _savePanel() {
    final panel = widget.panel!;
    return _save(() async => [await _crop(panel.page, panel.rect)], 'Panel');
  }

  @override
  Widget build(BuildContext context) {
    final n = _picked.length;
    final canSave = !kIsWeb;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Share or save', style: AppText.heading(size: 20)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                _hasScreen
                    ? 'What you see goes by default; tick pages to add them. '
                        'The title, chapter, source and links go with them.'
                    : 'Tick pages to send together. The title, chapter, '
                        'source and links go with them.',
                style: AppText.body(size: 13, color: AppColors.text60),
              ),
            ),
            SizedBox(
              height: 168,
              child: ListView.separated(
                controller: _strip,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: widget.book.pageCount + (_hasScreen ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, k) {
                  final i = _hasScreen ? k - 1 : k;
                  return _Thumb(
                    page: _page(i),
                    label: i == _onScreen ? 'On screen' : 'P. ${i + 1}',
                    semantics: i == _onScreen ? 'What you see' : 'Page ${i + 1}',
                    picked: _picked.contains(i),
                    onTap: () => setState(() {
                      // At least one stays ticked.
                      if (!_picked.remove(i) || _picked.isEmpty) _picked.add(i);
                    }),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            FutureBuilder<String>(
              future: _caption,
              builder: (context, snap) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  snap.data?.split('\n').take(2).join('  ·  ') ?? ' ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.mono(size: 11, color: AppColors.text60),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  KeyedSubtree(
                    key: _shareButton,
                    child: InkButton(
                      icon: Icons.ios_share_rounded,
                      label: n == 1 ? 'Share page' : 'Share $n pages',
                      filled: true,
                      onTap: _busy ? null : _share,
                    ),
                  ),
                  if (canSave)
                    InkButton(
                      icon: Icons.download_rounded,
                      label: n == 1 ? 'Save to Photos' : 'Save $n to Photos',
                      onTap: _busy ? null : _savePages,
                    ),
                  if (canSave && widget.panel != null)
                    InkButton(
                      icon: Icons.crop_rounded,
                      label: 'Save this panel',
                      onTap: _busy ? null : _savePanel,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final Future<Uint8List> page;
  final String label;
  final String semantics;
  final bool picked;
  final VoidCallback onTap;

  const _Thumb({
    required this.page,
    required this.label,
    required this.semantics,
    required this.picked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: picked,
      label: semantics,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 104,
          child: Column(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: picked ? AppColors.accent : AppColors.border,
                      width: picked ? 3 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FutureBuilder<Uint8List>(
                        future: page,
                        builder: (context, snap) => snap.hasData
                            ? Image.memory(
                                snap.data!,
                                // Strips are long; show their top.
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                cacheWidth: 208,
                                errorBuilder: (_, _, _) => const SizedBox(),
                              )
                            : const SizedBox(),
                      ),
                      if (picked)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Icon(
                            Icons.check_circle_rounded,
                            size: 22,
                            color: AppColors.accent,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: AppText.mono(
                  size: 10.5,
                  color: picked ? AppColors.accentLink : AppColors.text60,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// JPEG and PNG go as they are; anything else (WebP, which chats often turn
/// into a sticker or a file) becomes PNG.
Future<(Uint8List, String, String)> _shareable(Uint8List bytes) async {
  if (bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return (bytes, 'jpg', 'image/jpeg');
  }
  if (bytes.length > 3 && bytes[0] == 0x89 && bytes[1] == 0x50) {
    return (bytes, 'png', 'image/png');
  }
  final image = await _decode(bytes);
  try {
    return (await _png(image), 'png', 'image/png');
  } finally {
    image.dispose();
  }
}

/// The page as is, or a webtoon strip in pieces (see [stripCuts]).
Future<List<Uint8List>> _pieces(Uint8List bytes) async {
  final image = await _decode(bytes);
  try {
    final cuts = stripCuts(image.width, image.height);
    if (cuts.length == 1) return [bytes];
    final w = image.width.toDouble();
    return [
      for (final (top, bottom) in cuts)
        await _cut(image, Rect.fromLTRB(0, top.toDouble(), w, bottom.toDouble())),
    ];
  } finally {
    image.dispose();
  }
}

/// Just the panel, at the page's full resolution.
Future<Uint8List> _crop(Uint8List bytes, PanelRect r) async {
  final image = await _decode(bytes);
  try {
    return await _cut(
      image,
      Rect.fromLTWH(
        r.left * image.width,
        r.top * image.height,
        r.width * image.width,
        r.height * image.height,
      ),
    );
  } finally {
    image.dispose();
  }
}

/// [src] of [image] as PNG, at full resolution.
Future<Uint8List> _cut(ui.Image image, Rect src) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    image,
    src,
    Offset.zero & src.size,
    Paint()..filterQuality = FilterQuality.high,
  );
  final cropped = await recorder.endRecording().toImage(
    src.width.round().clamp(1, image.width),
    src.height.round().clamp(1, image.height),
  );
  try {
    return await _png(cropped);
  } finally {
    cropped.dispose();
  }
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

Future<Uint8List> _png(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
