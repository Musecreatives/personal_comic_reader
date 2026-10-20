import 'dart:async';

import '../../backends/suwayomi/suwayomi_backend.dart';
import 'paperback_backup.dart';
import 'source_mapping.dart';

enum MatchStatus { highConfidence, review, lowConfidence, noResults, noMappableSource }

class TitleMatch {
  final PaperbackTitle title;
  MatchStatus status;
  PaperbackSource? matchedSource;
  String? suwayomiSourceId;
  int? suwayomiMangaId;
  String? suwayomiMangaTitle;
  double score;
  bool excluded;

  TitleMatch({
    required this.title,
    required this.status,
    this.matchedSource,
    this.suwayomiSourceId,
    this.suwayomiMangaId,
    this.suwayomiMangaTitle,
    this.score = 0,
    this.excluded = false,
  });
}

/// Progress events emitted while matching or applying, so the UI can show
/// real per-title status instead of a single spinner over a multi-minute
/// operation.
sealed class ImportEvent {}

class MatchProgress extends ImportEvent {
  final int done;
  final int total;
  final TitleMatch latest;
  MatchProgress(this.done, this.total, this.latest);
}

class ApplyProgress extends ImportEvent {
  final int done;
  final int total;
  final String titleName;
  final bool ok;
  final String? error;
  ApplyProgress(this.done, this.total, this.titleName, {required this.ok, this.error});
}

/// Coordinates matching a parsed [PaperbackBackup] against a live Suwayomi
/// server's source catalogs, then (on request) actually applying the
/// approved matches - library adds, category creation, chapter progress.
///
/// Matching hits real external scraper sites through Suwayomi and is
/// rate-limit sensitive (learned the hard way during the manual version of
/// this migration): requests to the same source are serialized with
/// backoff; different sources run concurrently.
class BackupImportController {
  final SuwayomiBackend backend;
  BackupImportController({required this.backend});

  Map<String, String>? _sourceNameToId;

  Future<Map<String, String>> _resolveSourceIds() async {
    if (_sourceNameToId != null) return _sourceNameToId!;
    final installed = await backend.listInstalledSources();
    final map = <String, String>{};
    for (final s in installed) {
      map[s.name] = s.id;
    }
    _sourceNameToId = map;
    return map;
  }

  String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  double _similarity(String a, String b) {
    final ta = _normalize(a).split(' ').where((w) => w.isNotEmpty).toSet();
    final tb = _normalize(b).split(' ').where((w) => w.isNotEmpty).toSet();
    if (ta.isEmpty || tb.isEmpty) return 0;
    final overlap = ta.intersection(tb).length;
    final union = ta.union(tb).length;
    return overlap / union;
  }

  Future<T> _withBackoff<T>(Future<T> Function() fn, {int retries = 5}) async {
    var delay = const Duration(seconds: 2);
    for (var i = 0; i <= retries; i++) {
      try {
        return await fn();
      } catch (e) {
        if (i == retries) rethrow;
        await Future.delayed(delay);
        delay *= 1.7;
        if (delay > const Duration(seconds: 20)) delay = const Duration(seconds: 20);
      }
    }
    throw StateError('unreachable');
  }

  /// Matches every title in [backup] against Suwayomi source catalogs,
  /// yielding one [MatchProgress] per title as results come in.
  Stream<ImportEvent> match(PaperbackBackup backup) async* {
    final sourceIds = await _resolveSourceIds();
    final results = <TitleMatch>[];
    var done = 0;

    // Group titles by which Suwayomi source they'd search, so requests to
    // the same source are serialized (courtesy delay) while different
    // sources proceed in parallel.
    final bySource = <String, List<PaperbackTitle>>{};
    final unmappable = <PaperbackTitle>[];
    for (final title in backup.titles) {
      PaperbackSource? mappable;
      String? suwayomiName;
      for (final s in title.sources) {
        final name = paperbackToSuwayomiSourceName[s.sourceId];
        if (name != null && sourceIds.containsKey(name)) {
          mappable = s;
          suwayomiName = name;
          break;
        }
      }
      if (mappable == null || suwayomiName == null) {
        unmappable.add(title);
        continue;
      }
      (bySource[suwayomiName] ??= []).add(title);
    }

    final controller = StreamController<ImportEvent>();
    final total = backup.titles.length;

    Future<void> processSource(String suwayomiName, List<PaperbackTitle> titles) async {
      final sourceId = sourceIds[suwayomiName]!;
      for (final title in titles) {
        final source = title.sources.firstWhere(
            (s) => paperbackToSuwayomiSourceName[s.sourceId] == suwayomiName);
        try {
          final candidates = await _withBackoff(
              () => backend.searchSourceCatalog(sourceId, title.primaryTitle));
          final scored = candidates
              .map((c) => (id: c.id, title: c.title, score: _similarity(c.title, title.primaryTitle)))
              .toList()
            ..sort((a, b) => b.score.compareTo(a.score));
          final best = scored.isEmpty ? null : scored.first;

          final match = TitleMatch(
            title: title,
            status: best == null
                ? MatchStatus.noResults
                : best.score >= 0.8
                    ? MatchStatus.highConfidence
                    : best.score >= 0.4
                        ? MatchStatus.review
                        : MatchStatus.lowConfidence,
            matchedSource: source,
            suwayomiSourceId: sourceId,
            suwayomiMangaId: best?.id,
            suwayomiMangaTitle: best?.title,
            score: best?.score ?? 0,
          );
          results.add(match);
          done++;
          controller.add(MatchProgress(done, total, match));
        } catch (e) {
          final match = TitleMatch(
              title: title, status: MatchStatus.noResults, matchedSource: source);
          results.add(match);
          done++;
          controller.add(MatchProgress(done, total, match));
        }
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }

    unawaited(() async {
      await Future.wait(bySource.entries.map((e) => processSource(e.key, e.value)));
      for (final title in unmappable) {
        final match = TitleMatch(title: title, status: MatchStatus.noMappableSource);
        results.add(match);
        done++;
        controller.add(MatchProgress(done, total, match));
      }
      await controller.close();
    }());

    yield* controller.stream;
  }

  /// Applies every non-excluded [MatchStatus.highConfidence] match: adds
  /// the title to the Suwayomi library, recreates its Paperback tabs as
  /// categories, and pushes chapter read/unread state. Nothing here writes
  /// anywhere else - Kapowarr/CLU acquisition for the unmapped titles is a
  /// separate, manual step by design.
  Stream<ImportEvent> apply(
      List<TitleMatch> matches, PaperbackBackup backup) async* {
    final toApply = matches
        .where((m) => m.status == MatchStatus.highConfidence && !m.excluded)
        .toList();
    final categoryCache = <String, int>{};
    var done = 0;

    for (final match in toApply) {
      final mangaId = match.suwayomiMangaId;
      if (mangaId == null) continue;
      try {
        final catIds = <int>[];
        for (final tab in match.title.tabs) {
          catIds.add(categoryCache[tab] ??= await backend.ensureCategory(tab));
        }
        await backend.addToLibraryWithCategories(mangaId, catIds);

        final source = match.matchedSource;
        final progress = source == null
            ? const <PaperbackChapterProgress>[]
            : backup.progressBySourceManga[source.sourceUuid] ?? const [];
        if (progress.isNotEmpty) {
          final byNumber = await backend.fetchChapterIdsByNumber(mangaId);
          final readIds = <int>[];
          for (final p in progress) {
            if (!p.completed) continue;
            final id = byNumber[p.chapNum];
            if (id != null) readIds.add(id);
          }
          if (readIds.isNotEmpty) await backend.markChaptersRead(readIds);
        }

        done++;
        yield ApplyProgress(done, toApply.length, match.title.primaryTitle, ok: true);
      } catch (e) {
        done++;
        yield ApplyProgress(done, toApply.length, match.title.primaryTitle,
            ok: false, error: '$e');
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }
}
