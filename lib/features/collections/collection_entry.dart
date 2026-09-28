import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
import '../../core/collections/collection.dart';

/// A collection entry looked up on its own server.
typedef ResolvedEntry = ({ReaderBackend backend, Series series});

/// Resolves one [collectionEntry] - null when its server isn't configured on
/// this device or the series is gone.
final collectionEntryProvider =
    FutureProvider.family<ResolvedEntry?, String>((ref, entry) async {
  final parsed = parseCollectionEntry(entry);
  final backend =
      await ref.watch(backendForServerKeyProvider(parsed.serverKey).future);
  if (backend == null) return null;
  try {
    return (backend: backend, series: await backend.getSeries(parsed.seriesId));
  } catch (_) {
    return null;
  }
});

/// Opens a resolved entry's series page, switching to its server first -
/// the series screen reads whichever server is active.
Future<void> openCollectionEntry(
    BuildContext context, WidgetRef ref, ResolvedEntry e) async {
  await activateServer(ref, e.backend.config.id);
  if (context.mounted) {
    context.push('/series/${Uri.encodeComponent(e.series.id)}');
  }
}
