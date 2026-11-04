import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
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

/// Share pages to a chat with where they're from, or save them to Photos.
/// The page you're on starts ticked; tick more from the chapter and they
/// go out as one post. [panel] is set in panel mode, to save just that one.
Future<void> showSharePagesSheet(
  BuildContext context, {
  required ReaderBackend backend,
  required PageCache pageCache,
  required Book book,
  required Book main,
  required int currentPage,
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
  final ({Uint8List page, PanelRect rect})? panel;

  const _SharePagesSheet({
    required this.backend,
    required this.pageCache,
    required this.book,
    required this.main,
    required this.currentPage,
    this.panel,
  });

  @override
  State<_SharePagesSheet> createState() => _SharePagesSheetState();
}

class _SharePagesSheetState extends State<_SharePagesSheet> {
  late final Set<int> _picked = {widget.currentPage};
  final _pages = <int, Future<Uint8List>>{};
  final _shareButton = GlobalKey();
  late final ScrollController _strip = ScrollController(
    // Open with the current page in view (thumbnails are 104 wide).
    initialScrollOffset: (widget.currentPage * 112.0 - 120).clamp(0, double.infinity),
  );
  late final Future<String> _caption = _buildCaption();
  bool _busy = false;

  Future<Uint8List> _page(int i) => _pages[i] ??=
      widget.pageCache.getPage(widget.backend, widget.book.id, i);

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
      pages: _picked.toList(),
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

  String _fileName(int page, String ext) {
    final slug = widget.main.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return '$slug-ch${formatChapterNumber(widget.main.number)}-p${page + 1}.$ext';
  }

  Future<void> _share() => _run(() async {
    final files = <XFile>[];
    for (final i in _sorted) {
      final (bytes, ext, mime) = await _shareable(await _page(i));
      files.add(XFile.fromData(bytes, name: _fileName(i, ext), mimeType: mime));
    }
    // Rebuilt so the page list in the caption matches what's ticked.
    final caption = await _buildCaption();
    // Some chats drop the text when several pictures go together; it's on
    // the clipboard to paste.
    await Clipboard.setData(ClipboardData(text: caption));
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // WhatsApp's iOS share extension closes at once when pictures come with
    // text, so on iOS the caption goes by clipboard only. The device's OS,
    // not PlatformStyle: a forced Android look on an iPhone still has this.
    final pasteCaption = defaultTargetPlatform == TargetPlatform.iOS;
    final box = _shareButton.currentContext?.findRenderObject() as RenderBox?;
    final result = await SharePlus.instance.share(
      ShareParams(
        files: files,
        text: pasteCaption ? null : caption,
        subject: caption.split('\n').first,
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

  Future<void> _save(List<Uint8List> images, String what) => _run(() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await Gal.hasAccess(toAlbum: true) &&
          !await Gal.requestAccess(toAlbum: true)) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Allow Photos access in Settings to save pages'),
        ));
        return;
      }
      for (final bytes in images) {
        final (data, _, _) = await _shareable(bytes);
        await Gal.putImageBytes(data, album: 'Shaddai Reader');
      }
      messenger.showSnackBar(SnackBar(content: Text('$what saved to Photos')));
      if (mounted) Navigator.of(context).pop();
    } on GalException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text("Couldn't save: ${e.type.message}"),
      ));
    }
  });

  Future<void> _savePages() async {
    final images = [for (final i in _sorted) await _page(i)];
    final n = images.length;
    await _save(images, n == 1 ? 'Page' : '$n pages');
  }

  Future<void> _savePanel() async {
    final panel = widget.panel!;
    await _save([await _crop(panel.page, panel.rect)], 'Panel');
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
                'Tick pages to send together. The title, chapter, source and '
                'links go with them.',
                style: AppText.body(size: 13, color: AppColors.text60),
              ),
            ),
            SizedBox(
              height: 168,
              child: ListView.separated(
                controller: _strip,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: widget.book.pageCount,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) => _Thumb(
                  page: _page(i),
                  index: i,
                  picked: _picked.contains(i),
                  onTap: () => setState(() {
                    // At least one page stays ticked.
                    if (!_picked.remove(i) || _picked.isEmpty) _picked.add(i);
                  }),
                ),
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
  final int index;
  final bool picked;
  final VoidCallback onTap;

  const _Thumb({
    required this.page,
    required this.index,
    required this.picked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: picked,
      label: 'Page ${index + 1}',
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
                'P. ${index + 1}',
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

/// Just the panel, at the page's full resolution.
Future<Uint8List> _crop(Uint8List bytes, PanelRect r) async {
  final image = await _decode(bytes);
  final src = Rect.fromLTWH(
    r.left * image.width,
    r.top * image.height,
    r.width * image.width,
    r.height * image.height,
  );
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
    image.dispose();
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
