import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/core/discovery/comic_recommender.dart';
import 'package:shaddai_reader/core/kapowarr/kapowarr_client.dart';

KapowarrVolume vol(String title, int year, [String publisher = 'DC Comics']) =>
    KapowarrVolume(
      id: title.hashCode,
      title: title,
      year: year,
      publisher: publisher,
      volumeNumber: 1,
      monitored: true,
      issueCount: 10,
      issuesDownloaded: 10,
      folder: '',
    );

KapowarrSearchResult hit(int id, String title, int year,
        {String publisher = 'DC Comics', int issues = 12, bool added = false}) =>
    KapowarrSearchResult(
      comicvineId: id,
      title: title,
      year: year,
      volumeNumber: 1,
      coverUrl: '',
      description: '',
      publisher: publisher,
      issueCount: issues,
      alreadyAdded: added,
    );

void main() {
  test('title cores drop qualifiers, years and subtitles', () {
    expect(ComicRecommender.core('Absolute Wonder Woman'), 'wonder woman');
    expect(ComicRecommender.core('The Amazing Spider-Man (2022)'), 'spider-man');
    expect(ComicRecommender.core('Batman: The Long Halloween'), 'batman');
    expect(ComicRecommender.core('Nightwing Vol. 4'), 'nightwing');
  });

  test('the most repeated franchises become search terms first', () {
    final terms = ComicRecommender.searchTerms([
      vol('Absolute Batman', 2024),
      vol('Batman', 2016),
      vol('Nightwing', 2021),
      vol('The Flash', 2023),
    ], limit: 2);
    expect(terms, ['batman', 'flash']);
  });

  test('ranking skips owned and empty volumes, prefers recent familiar ones', () {
    final library = [vol('Batman', 2016), vol('Nightwing', 2021)];
    final recs = ComicRecommender.rank(
      library,
      {
        'batman': [
          hit(1, 'Batman', 1940),
          hit(2, 'Batman', 2016), // already in the library
          hit(3, 'Batman and Robin', 2023),
          hit(4, 'Batman Beyond', 2025, added: true),
          hit(5, 'Batman: Empty', 2025, issues: 0),
          hit(6, 'Batman Adventures', 2024, publisher: 'Other'),
        ],
        'nightwing': [hit(3, 'Batman and Robin', 2023)], // duplicate
      },
      currentYear: 2026,
    );
    expect(recs.map((r) => r.volume.comicvineId), [3, 6, 1]);
  });
}
