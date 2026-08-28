import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// One title in a Paperback library, resolved across its
/// `__LIBRARY_MANGA_V5` / `__SOURCE_MANGA_V5` / `__MANGA_INFO_V5` records.
class PaperbackTitle {
  final String libraryId;
  final String primaryTitle;
  final List<String> tabs;
  final List<PaperbackSource> sources;

  const PaperbackTitle({
    required this.libraryId,
    required this.primaryTitle,
    required this.tabs,
    required this.sources,
  });
}

class PaperbackSource {
  final String sourceUuid;
  final String sourceId; // e.g. "MangaBat" - the scraper site's own id
  final String paperbackMangaId; // that site's id/slug for this title
  final int chapterCount;
  final int readCount;

  const PaperbackSource({
    required this.sourceUuid,
    required this.sourceId,
    required this.paperbackMangaId,
    required this.chapterCount,
    required this.readCount,
  });
}

/// One chapter's read state for a given [PaperbackSource], used to
/// reconcile progress once a title is matched to a Suwayomi source.
class PaperbackChapterProgress {
  final double chapNum;
  final bool completed;

  const PaperbackChapterProgress({required this.chapNum, required this.completed});
}

class PaperbackBackup {
  final List<PaperbackTitle> titles;

  /// Keyed by source-manga UUID (the same key as [PaperbackSource.sourceUuid]).
  final Map<String, List<PaperbackChapterProgress>> progressBySourceManga;

  const PaperbackBackup({required this.titles, required this.progressBySourceManga});
}

/// Parses a Paperback `.pas5` backup: a zip of flat JSON dictionaries
/// (`{uuid: {...}}`) that cross-reference each other via
/// `{"type": "...", "id": "..."}` refs, with the chapter and progress
/// tables sharded across several `-N` suffixed files.
class PaperbackBackupParser {
  static PaperbackBackup parse(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, Map<String, dynamic>>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name.split('/').last;
      if (!name.startsWith('__')) continue;
      final content = utf8.decode(file.content as List<int>);
      files[name] = jsonDecode(content) as Map<String, dynamic>;
    }

    final libraryManga = files['__LIBRARY_MANGA_V5'] ?? const {};
    final sourceManga = files['__SOURCE_MANGA_V5'] ?? const {};
    final mangaInfo = files['__MANGA_INFO_V5'] ?? const {};

    // Chapter + progress tables are sharded (-1, -2, ...); merge every
    // shard that exists rather than assuming a fixed count.
    final chapters = <String, Map<String, dynamic>>{};
    final progressMarkers = <Map<String, dynamic>>[];
    for (final entry in files.entries) {
      if (entry.key.startsWith('__CHAPTER_V5')) {
        for (final c in entry.value.values) {
          chapters[(c as Map<String, dynamic>)['id'] as String] = c;
        }
      } else if (entry.key.startsWith('__CHAPTER_PROGRESS_MARKER_V5')) {
        progressMarkers.addAll(entry.value.values.cast<Map<String, dynamic>>());
      }
    }

    // chapter UUID -> sourceManga UUID, chapNum
    final chapterMeta = <String, ({String sourceMangaId, double chapNum})>{};
    for (final c in chapters.values) {
      final sm = c['sourceManga'] as Map<String, dynamic>?;
      if (sm == null) continue;
      chapterMeta[c['id'] as String] = (
        sourceMangaId: sm['id'] as String,
        chapNum: (c['chapNum'] as num?)?.toDouble() ?? 0,
      );
    }

    // sourceManga UUID -> read chapter progress list
    final progressBySourceManga = <String, List<PaperbackChapterProgress>>{};
    for (final marker in progressMarkers) {
      final chapterRef = marker['chapter'] as Map<String, dynamic>?;
      if (chapterRef == null) continue;
      final meta = chapterMeta[chapterRef['id'] as String];
      if (meta == null) continue;
      (progressBySourceManga[meta.sourceMangaId] ??= []).add(
        PaperbackChapterProgress(
          chapNum: meta.chapNum,
          completed: marker['completed'] as bool? ?? false,
        ),
      );
    }

    // Chapter counts per source-manga (independent of progress markers, so
    // a never-opened chapter still counts).
    final chapterCountBySourceManga = <String, int>{};
    for (final meta in chapterMeta.values) {
      chapterCountBySourceManga[meta.sourceMangaId] =
          (chapterCountBySourceManga[meta.sourceMangaId] ?? 0) + 1;
    }

    final titles = <PaperbackTitle>[];
    for (final entry in libraryManga.entries) {
      final lib = entry.value as Map<String, dynamic>;
      final attached = (lib['attachedSources'] as List?) ?? const [];
      final sources = <PaperbackSource>[];
      String? primaryTitle;

      for (final ref in attached) {
        final smId = (ref as Map<String, dynamic>)['id'] as String;
        final sm = sourceManga[smId] as Map<String, dynamic>?;
        if (sm == null) continue;
        final infoRef = sm['mangaInfo'] as Map<String, dynamic>?;
        final info = infoRef == null ? null : mangaInfo[infoRef['id']] as Map<String, dynamic>?;
        primaryTitle ??= info?['primaryTitle'] as String?;
        final readCount = (progressBySourceManga[smId] ?? const [])
            .where((p) => p.completed)
            .length;
        sources.add(PaperbackSource(
          sourceUuid: smId,
          sourceId: sm['sourceId'] as String? ?? '',
          paperbackMangaId: sm['mangaId'] as String? ?? '',
          chapterCount: chapterCountBySourceManga[smId] ?? 0,
          readCount: readCount,
        ));
      }

      if (primaryTitle == null || sources.isEmpty) continue;

      final tabs = ((lib['libraryTabs'] as List?) ?? const [])
          .map((t) => (t as Map<String, dynamic>)['name'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

      titles.add(PaperbackTitle(
        libraryId: entry.key,
        primaryTitle: primaryTitle,
        tabs: tabs,
        sources: sources,
      ));
    }

    return PaperbackBackup(titles: titles, progressBySourceManga: progressBySourceManga);
  }
}
