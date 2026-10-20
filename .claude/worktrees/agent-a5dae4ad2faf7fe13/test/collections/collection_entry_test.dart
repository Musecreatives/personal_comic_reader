import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/core/collections/collection.dart';

void main() {
  test('an entry round-trips its server key and series id', () {
    final e = collectionEntry('suwayomi|http://host:4567', '301');
    final parsed = parseCollectionEntry(e);
    expect(parsed.serverKey, 'suwayomi|http://host:4567');
    expect(parsed.seriesId, '301');
  });

  test('an OPDS feed URL as the series id survives intact', () {
    const id = 'http://host/opds/v1.2/series/abc?x=1|2';
    final parsed = parseCollectionEntry(collectionEntry('opds|http://host', id));
    expect(parsed.seriesId, id);
  });

  test('entries saved before servers were recorded mean the active server', () {
    final parsed = parseCollectionEntry('301');
    expect(parsed.serverKey, isNull);
    expect(parsed.seriesId, '301');
  });
}
