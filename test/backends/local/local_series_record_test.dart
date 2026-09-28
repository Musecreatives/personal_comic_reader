import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/backends/local/local_library_store.dart';

LocalSeriesRecord _roundTrip(LocalSeriesRecord r) => LocalSeriesRecord.fromJson(
    jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);

void main() {
  test('records saved with the old credits/tags keys split into fields', () {
    final r = LocalSeriesRecord.fromJson({
      'id': 's1',
      'title': 'Black Panther',
      'addedAt': '2026-01-01T00:00:00.000',
      'summary': 'Wakanda, in space.',
      'credits': 'Ta-Nehisi Coates · Daniel Acuña',
      'tags': ['2018', 'Marvel', 'Superhero', 'Sci-Fi'],
    });
    expect(r.writer, 'Ta-Nehisi Coates');
    expect(r.artist, 'Daniel Acuña');
    expect(r.year, '2018');
    expect(r.publisher, 'Marvel');
    expect(r.genres, ['Superhero', 'Sci-Fi']);
    // The header reads the same as before the migration.
    expect(r.credits, 'Ta-Nehisi Coates · Daniel Acuña');
    expect(r.tags, ['2018', 'Marvel', 'Superhero', 'Sci-Fi']);

    // Saving writes the new keys only.
    final json = r.toJson();
    expect(json.containsKey('credits'), isFalse);
    expect(json.containsKey('tags'), isFalse);
    expect(_roundTrip(r).tags, r.tags);
  });

  test('old records with a single credit and no year', () {
    final r = LocalSeriesRecord.fromJson({
      'id': 's1',
      'title': 'X',
      'addedAt': '2026-01-01T00:00:00.000',
      'credits': 'Solo Creator',
      'tags': ['Image'],
    });
    expect(r.writer, 'Solo Creator');
    expect(r.artist, isNull);
    expect(r.year, isNull);
    expect(r.publisher, 'Image');
    expect(r.genres, isEmpty);
  });

  test('withDetails replaces every field, clearing blanks; copyWith keeps', () {
    final r = LocalSeriesRecord(
      id: 's1',
      title: 'Old',
      addedAt: DateTime(2026),
      contentKind: 'comic',
      summary: 'Old summary',
      writer: 'W',
      artist: 'A',
      publisher: 'P',
      year: '2000',
      genres: const ['G'],
    );

    expect(r.copyWith(summary: null).summary, 'Old summary');

    final edited = _roundTrip(r.withDetails(title: 'New', writer: 'W2'));
    expect(edited.id, 's1');
    expect(edited.addedAt, r.addedAt);
    expect(edited.contentKind, 'comic');
    expect(edited.title, 'New');
    expect(edited.summary, isNull);
    expect(edited.writer, 'W2');
    expect(edited.artist, isNull);
    expect(edited.publisher, isNull);
    expect(edited.year, isNull);
    expect(edited.genres, isEmpty);
    expect(edited.credits, 'W2');
    expect(edited.tags, isEmpty);
  });
}
