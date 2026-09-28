import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../backends/local/local_backend.dart';

/// First page of an imported book, for covers where pages aren't files
/// (web keeps them in Hive).
final _localCoverProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, bookId) =>
        ref.watch(localLibraryStoreProvider).getPage(bookId, 0));

/// Cover art for a series/book, with a graceful placeholder while loading
/// and a fallback icon when there's no image or it fails to load.
///
/// [imageBytes] takes priority when set - used for locally-imported comics,
/// which have no server to fetch a thumbnail URL from.
class SeriesCover extends ConsumerWidget {
  final String? imageUrl;
  final Uint8List? imageBytes;
  final Map<String, String> headers;
  final BoxFit fit;

  const SeriesCover({
    super.key,
    required this.imageUrl,
    this.imageBytes,
    this.headers = const {},
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var bytes = imageBytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: fit,
        errorBuilder: (context, error, stack) => const _CoverFallback(),
      );
    }
    final url = imageUrl;
    if (url != null && url.startsWith('$localPageScheme:')) {
      bytes = ref
          .watch(_localCoverProvider(url.substring(localPageScheme.length + 1)))
          .valueOrNull;
      if (bytes == null) return const _CoverFallback();
      return Image.memory(
        bytes,
        fit: fit,
        cacheWidth: 360,
        errorBuilder: (context, error, stack) => const _CoverFallback(),
      );
    }
    if (url == null || url.isEmpty) {
      return const _CoverFallback();
    }
    // Imported comics on desktop: page 0 straight off disk.
    if (url.startsWith('file:')) {
      return Image.file(
        File.fromUri(Uri.parse(url)),
        fit: fit,
        cacheWidth: 360,
        errorBuilder: (context, error, stack) => const _CoverFallback(),
      );
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
