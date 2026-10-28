import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../comicvine/comicvine_client.dart';
import '../debug/debug_log.dart';
import '../kapowarr/kapowarr_client.dart' show plainText;

/// Publication status in the shape both Komga and the app understand.
enum SeriesStatus { ongoing, ended, hiatus, abandoned }

/// A cover and details for a series, found on an outside catalogue. The
/// owner picks one in "Refresh cover & details"; nothing is applied
/// automatically.
class CoverCandidate {
  final String source; // ANILIST, MANGADEX, COMICVINE
  final String title;
  final List<String> altTitles;
  final int? year;
  final String coverUrl;

  /// A wide image for the series page backdrop (AniList only).
  final String? bannerUrl;
  final String? description;
  final List<String> genres;
  final SeriesStatus? status;

  const CoverCandidate({
    required this.source,
    required this.title,
    required this.coverUrl,
    this.altTitles = const [],
    this.year,
    this.bannerUrl,
    this.description,
    this.genres = const [],
    this.status,
  });
}

/// What to write to the server. Null fields are left as they are.
class MetadataUpdate {
  final String? coverUrl;
  final String? bannerUrl;
  final String? summary;
  final List<String>? genres;
  final SeriesStatus? status;

  const MetadataUpdate({this.coverUrl, this.bannerUrl, this.summary, this.genres, this.status});
}

/// A backend that can take a new cover and details for a series: Komga
/// (uploaded and locked) and Suwayomi (kept in manga meta).
abstract class SeriesMetadataEditor {
  /// Whether a banner can be stored (Komga has nowhere to keep one).
  bool get supportsBanner;
  Future<void> applyMetadata(String seriesId, MetadataUpdate update);
}

// ---------------------------------------------------------------------------
// Parsing (kept pure so recorded responses can be tested)
// ---------------------------------------------------------------------------

String? _text(Object? v) {
  final s = v is String ? v.trim() : null;
  return s == null || s.isEmpty ? null : s;
}

SeriesStatus? _anilistStatus(Object? s) => switch (s) {
      'RELEASING' => SeriesStatus.ongoing,
      'FINISHED' => SeriesStatus.ended,
      'HIATUS' => SeriesStatus.hiatus,
      'CANCELLED' => SeriesStatus.abandoned,
      _ => null,
    };

List<CoverCandidate> parseAniList(Map<String, dynamic> json) {
  final media = (json['data']?['Page']?['media'] as List?) ?? const [];
  final out = <CoverCandidate>[];
  for (final m in media.cast<Map<String, dynamic>>()) {
    final cover = _text(m['coverImage']?['extraLarge']);
    if (cover == null) continue;
    final title = m['title'] as Map? ?? const {};
    final description = _text(m['description']);
    out.add(CoverCandidate(
      source: 'ANILIST',
      title: _text(title['english']) ?? _text(title['romaji']) ?? 'Untitled',
      altTitles: [
        for (final t in [title['romaji'], title['english'], title['native'], ...?(m['synonyms'] as List?)])
          ?_text(t),
      ],
      year: m['startDate']?['year'] as int?,
      coverUrl: cover,
      bannerUrl: _text(m['bannerImage']),
      description: description == null ? null : plainText(description),
      genres: ((m['genres'] as List?) ?? const []).whereType<String>().toList(),
      status: _anilistStatus(m['status']),
    ));
  }
  return out;
}

List<CoverCandidate> parseMangaDex(Map<String, dynamic> json) {
  final data = (json['data'] as List?) ?? const [];
  String? en(Object? map) =>
      map is Map ? _text(map['en']) ?? _text(map.values.firstOrNull) : null;
  final out = <CoverCandidate>[];
  for (final m in data.cast<Map<String, dynamic>>()) {
    final a = (m['attributes'] as Map?)?.cast<String, dynamic>() ?? const {};
    final file = [
      for (final r in (m['relationships'] as List?) ?? const [])
        if (r is Map && r['type'] == 'cover_art') _text(r['attributes']?['fileName']),
    ].nonNulls.firstOrNull;
    if (file == null) continue;
    out.add(CoverCandidate(
      source: 'MANGADEX',
      title: en(a['title']) ?? 'Untitled',
      altTitles: [for (final t in (a['altTitles'] as List?) ?? const []) ?en(t)],
      year: a['year'] as int?,
      coverUrl: 'https://uploads.mangadex.org/covers/${m['id']}/$file',
      description: en(a['description']),
      genres: [
        for (final t in (a['tags'] as List?) ?? const [])
          if (t is Map && t['attributes']?['group'] == 'genre') ?en(t['attributes']?['name']),
      ],
      status: switch (a['status']) {
        'ongoing' => SeriesStatus.ongoing,
        'completed' => SeriesStatus.ended,
        'hiatus' => SeriesStatus.hiatus,
        'cancelled' => SeriesStatus.abandoned,
        _ => null,
      },
    ));
  }
  return out;
}

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();

/// How well [candidate] matches [query], 0 to 1: an exact title or alt
/// title 1, one containing the other 0.9, otherwise the share of words.
double titleScore(String query, CoverCandidate candidate) {
  final q = _norm(query);
  if (q.isEmpty) return 0;
  var best = 0.0;
  for (final t in [candidate.title, ...candidate.altTitles].map(_norm)) {
    if (t.isEmpty) continue;
    if (t == q) return 1;
    if (t.contains(q) || q.contains(t)) {
      if (best < 0.9) best = 0.9;
      continue;
    }
    final a = q.split(' ').toSet(), b = t.split(' ').toSet();
    final shared = a.intersection(b).length / a.union(b).length;
    if (shared > best) best = shared;
  }
  return best;
}

/// Best matches first; ties keep the order the sources answered in.
List<CoverCandidate> rankCandidates(String query, List<CoverCandidate> all) {
  final scored = [for (final (i, c) in all.indexed) (i: i, c: c, s: titleScore(query, c))];
  scored.sort((x, y) => y.s != x.s ? y.s.compareTo(x.s) : x.i.compareTo(y.i));
  return [for (final e in scored) e.c];
}

// ---------------------------------------------------------------------------
// Fetching
// ---------------------------------------------------------------------------

/// Looks a title up on AniList and MangaDex (both keyless) or, for comics,
/// ComicVine. These are outside sites, so this plain client never carries
/// a server login.
class CoverCandidateFinder {
  CoverCandidateFinder({Dio? dio, this.comicVine})
      : _dio = dio ??
            trackedDio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              headers: kIsWeb ? null : {'User-Agent': 'ShaddaiReader/1.0 (personal comic reader)'},
            ));

  final Dio _dio;
  final ComicVineClient? comicVine;

  static const _anilistQuery = r'''
query($q: String) { Page(perPage: 6) { media(search: $q, type: MANGA) {
  title { romaji english native } synonyms startDate { year } status genres
  description(asHtml: false) coverImage { extraLarge } bannerImage } } }''';

  /// Each catalogue answers on its own; one being down only removes its
  /// covers. [comics] asks ComicVine instead of the manga catalogues.
  Future<List<CoverCandidate>> search(String query, {bool comics = false}) async {
    final cv = comicVine;
    final lookups = <Future<List<CoverCandidate>>>[
      if (!comics) ...[
        _quiet(() async => parseAniList((await _dio.post<Map<String, dynamic>>(
              'https://graphql.anilist.co',
              data: {'query': _anilistQuery, 'variables': {'q': query}},
            ))
                .data!)),
        _quiet(() async => parseMangaDex((await _dio.get<Map<String, dynamic>>(
              'https://api.mangadex.org/manga',
              queryParameters: {'title': query, 'limit': 6, 'includes[]': 'cover_art'},
            ))
                .data!)),
      ],
      if (comics && cv != null)
        _quiet(() async => [
              for (final v in (await cv.searchVolumes(query)).take(8))
                if (v.imageUrl != null)
                  CoverCandidate(
                    source: 'COMICVINE',
                    title: v.name,
                    year: int.tryParse(v.startYear ?? ''),
                    coverUrl: v.imageUrl!,
                    description: v.summary,
                  ),
            ]),
    ];
    return rankCandidates(query, [for (final r in await Future.wait(lookups)) ...r]);
  }

  Future<List<CoverCandidate>> _quiet(Future<List<CoverCandidate>> Function() run) async {
    try {
      return await run();
    } catch (_) {
      return const [];
    }
  }
}
