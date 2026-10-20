import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../debug/debug_log.dart';
import '../kapowarr/kapowarr_client.dart' show plainText;

/// A ComicVine volume (a series run). Search results carry the basics;
/// [ComicVineClient.volume] adds the summary and credits.
class ComicVineVolume {
  final int id;
  final String name;
  final String? startYear;
  final String? publisher;
  final String? thumbUrl;
  final int issueCount;
  final int? firstIssueId;

  /// Plain text (ComicVine sends HTML).
  final String? summary;
  final String? writer;
  final String? artist;

  const ComicVineVolume({
    required this.id,
    required this.name,
    this.startYear,
    this.publisher,
    this.thumbUrl,
    this.issueCount = 0,
    this.firstIssueId,
    this.summary,
    this.writer,
    this.artist,
  });

  factory ComicVineVolume.fromJson(Map<String, dynamic> j) {
    String? text(dynamic v) {
      final s = v is String ? v.trim() : null;
      return s == null || s.isEmpty ? null : s;
    }

    final description = text(j['description']);
    return ComicVineVolume(
      id: j['id'] as int,
      name: text(j['name']) ?? 'Untitled',
      startYear: text(j['start_year']),
      publisher: text((j['publisher'] as Map?)?['name']),
      thumbUrl: text((j['image'] as Map?)?['thumb_url']),
      issueCount: j['count_of_issues'] as int? ?? 0,
      firstIssueId: (j['first_issue'] as Map?)?['id'] as int?,
      summary: description == null ? text(j['deck']) : plainText(description),
    );
  }

  ComicVineVolume withCredits({String? writer, String? artist}) =>
      ComicVineVolume(
        id: id,
        name: name,
        startYear: startYear,
        publisher: publisher,
        thumbUrl: thumbUrl,
        issueCount: issueCount,
        firstIssueId: firstIssueId,
        summary: summary,
        writer: writer,
        artist: artist,
      );
}

/// Writer and artist from an issue's `person_credits`, whose roles are
/// comma-separated ("penciler, inker"). Artist prefers the penciller, like
/// ComicInfo parsing does, then inker, then cover artist.
({String? writer, String? artist}) creditsFromPersonCredits(List credits) {
  String? withRole(List<String> roles) {
    for (final role in roles) {
      for (final c in credits.cast<Map>()) {
        final has = '${c['role']}'
            .split(',')
            .map((r) => r.trim().toLowerCase())
            .contains(role);
        if (has && c['name'] is String) return c['name'] as String;
      }
    }
    return null;
  }

  return (
    writer: withRole(['writer']),
    artist: withRole(['penciler', 'penciller', 'artist', 'inker', 'cover']),
  );
}

/// A failure worded for the user.
class ComicVineException implements Exception {
  final String message;
  const ComicVineException(this.message);
  @override
  String toString() => message;
}

/// Direct ComicVine API client for looking up metadata on imported comics.
///
/// ComicVine sends no CORS headers, so from the web build the browser
/// blocks these requests; that surfaces as a [ComicVineException] saying
/// so rather than a proxy (desktop and mobile are unaffected).
class ComicVineClient {
  static const baseUrl = 'https://comicvine.gamespot.com/api';

  final Dio _dio;

  ComicVineClient({required String apiKey, Dio? dio})
    : _dio =
          dio ??
          trackedDio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              // ComicVine rejects generic/empty user agents. Browsers
              // forbid setting it, so web goes without.
              headers: kIsWeb
                  ? null
                  : {
                      'User-Agent':
                          'ShaddaiReader/1.0 (personal comic reader; '
                          'github.com/Musecreatives/personal_comic_reader)',
                    },
            ),
          ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.queryParameters['api_key'] = apiKey;
          options.queryParameters['format'] = 'json';
          handler.next(options);
        },
      ),
    );
  }

  Future<List<ComicVineVolume>> searchVolumes(String query) async {
    final results = await _get('/search/', {
      'resources': 'volume',
      'query': query,
      'limit': 20,
      'field_list': 'id,name,start_year,publisher,image,count_of_issues',
    });
    return (results as List)
        .map((e) => ComicVineVolume.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The volume's details, with writer/artist from its first issue's
  /// credits (volumes list people without roles). Credits are best-effort:
  /// if that second request fails the volume still comes back.
  Future<ComicVineVolume> volume(int id) async {
    final volume = ComicVineVolume.fromJson(
      await _get('/volume/4050-$id/', {
            'field_list':
                'id,name,start_year,publisher,image,count_of_issues,first_issue,description,deck',
          })
          as Map<String, dynamic>,
    );
    final issueId = volume.firstIssueId;
    if (issueId == null) return volume;
    try {
      final issue =
          await _get('/issue/4000-$issueId/', {'field_list': 'person_credits'})
              as Map<String, dynamic>;
      final credits = creditsFromPersonCredits(
        issue['person_credits'] as List? ?? const [],
      );
      return volume.withCredits(writer: credits.writer, artist: credits.artist);
    } on ComicVineException {
      return volume;
    }
  }

  /// `results` of a ComicVine response. ComicVine reports most errors in
  /// the body's status_code with HTTP 200; rate limiting is HTTP 420.
  Future<Object?> _get(String path, Map<String, dynamic> query) async {
    final Response res;
    try {
      res = await _dio.get(path, queryParameters: query);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      throw ComicVineException(switch (code) {
        420 || 429 => _rateLimited,
        401 || 403 => _badKey,
        // No response: offline, or (web) blocked by CORS.
        null =>
          kIsWeb
              ? "ComicVine can't be reached from the web app - it doesn't "
                    'allow browser requests (CORS). Use the desktop or '
                    'mobile app.'
              : "Couldn't reach ComicVine. Check your connection.",
        _ => 'ComicVine returned HTTP $code.',
      });
    }
    return parseResults(res.data);
  }

  static const _rateLimited =
      "ComicVine's rate limit was hit. Wait a few minutes and try again.";
  static const _badKey =
      'ComicVine rejected the API key. Check it in Settings.';

  /// Exposed for tests.
  static Object? parseResults(Object? data) {
    if (data is! Map) {
      throw const ComicVineException('Unexpected ComicVine response.');
    }
    return switch (data['status_code']) {
      1 => data['results'],
      100 => throw const ComicVineException(_badKey),
      107 => throw const ComicVineException(_rateLimited),
      101 => throw const ComicVineException('ComicVine has no such volume.'),
      _ => throw ComicVineException(
        'ComicVine: ${data['error'] ?? 'unknown error'}',
      ),
    };
  }
}
