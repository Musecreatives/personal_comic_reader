import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/core/discovery/recommender.dart';

TasteTitle owned(String title, List<String> genres, {String source = 's1'}) =>
    TasteTitle(title: title, genres: genres, sourceId: source);

Candidate cand(int id, String title, List<String> genres, {String source = 's1'}) =>
    Candidate(
        id: id, title: title, thumbnailUrl: 'u$id', genres: genres, sourceId: source);

void main() {
  // Action is on 5 of 6 titles (very common), Martial arts on 2 of 6.
  final library = [
    owned('A', ['Action', 'Martial arts']),
    owned('B', ['Action']),
    owned('C', ['Action']),
    owned('D', ['Action', 'Romance']),
    owned('E', ['Action', 'Comedy']),
    owned('F', ['Martial arts']),
  ];

  test('a ubiquitous genre weighs less than a distinguishing one', () {
    final w = Recommender.genreWeights(library);
    expect(w['action']! < w['martial arts']!, isTrue,
        reason: 'Action is on every title, so it says little about taste');
  });

  test('candidates matching the more distinctive genre rank first', () {
    final ranked = Recommender.rank(library, [
      cand(1, 'Only Action', ['Action']),
      cand(2, 'Fighter', ['Action', 'Martial arts']),
    ]);
    expect(ranked.map((r) => r.candidate.title), ['Fighter', 'Only Action']);
    expect(ranked.first.because, contains('martial arts'));
  });

  test('titles already in the library are never recommended', () {
    final ranked = Recommender.rank(library, [
      cand(1, 'a', ['Action', 'Martial arts']), // same as "A", different case
      cand(2, 'New One', ['Action', 'Martial arts']),
    ]);
    expect(ranked.map((r) => r.candidate.title), ['New One']);
  });

  test('the same title from two sources appears once, best score kept', () {
    final ranked = Recommender.rank(library, [
      cand(1, 'Twin!', ['Action'], source: 's1'),
      cand(2, 'twin', ['Action', 'Martial arts'], source: 's2'),
    ]);
    expect(ranked, hasLength(1));
    expect(ranked.single.candidate.id, 2);
  });

  test('candidates sharing no known genre are dropped', () {
    final ranked = Recommender.rank(library, [cand(1, 'Alien', ['Sci-fi'])]);
    expect(ranked, isEmpty);
  });

  test('topSources lists where the library actually comes from', () {
    final lib = [
      owned('1', ['x'], source: 'big'),
      owned('2', ['x'], source: 'big'),
      owned('3', ['x'], source: 'small'),
    ];
    expect(Recommender.topSources(lib, limit: 2), ['big', 'small']);
    expect(Recommender.topSources(lib, limit: 1), ['big']);
  });
}
