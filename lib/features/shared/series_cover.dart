import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Cover art for a series/book, with a graceful placeholder while loading
/// and a fallback icon when there's no image or it fails to load.
class SeriesCover extends StatelessWidget {
  final String? imageUrl;
  final Map<String, String> headers;
  final BoxFit fit;

  const SeriesCover({
    super.key,
    required this.imageUrl,
    this.headers = const {},
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) {
      return const _CoverFallback();
    }
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: headers,
      fit: fit,
      placeholder: (context, url) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
      ),
      errorWidget: (context, url, error) => const _CoverFallback(),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(
        Icons.menu_book_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        size: 32,
      ),
    );
  }
}
