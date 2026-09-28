import 'package:xml/xml.dart';

/// The fields we use from a ComicInfo.xml - the de-facto metadata file
/// (ComicRack's schema) that taggers like Mylar, Kapowarr and ComicTagger
/// drop inside CBZ/CBR archives.
class ComicInfo {
  final String? series;
  final String? number;
  final String? summary;
  final String? writer;
  final String? artist;
  final String? publisher;
  final String? year;
  final List<String> genres;

  const ComicInfo({
    this.series,
    this.number,
    this.summary,
    this.writer,
    this.artist,
    this.publisher,
    this.year,
    this.genres = const [],
  });

  /// Null when [xml] isn't a ComicInfo document - a malformed or foreign
  /// file just means no metadata, never a failed import.
  static ComicInfo? parse(String xml) {
    final XmlElement root;
    try {
      root = XmlDocument.parse(xml).rootElement;
    } catch (_) {
      return null;
    }
    if (root.name.local != 'ComicInfo') return null;

    String? field(String name) {
      final text = root.getElement(name)?.innerText.trim();
      return text == null || text.isEmpty ? null : text;
    }

    final year = field('Year');
    return ComicInfo(
      series: field('Series'),
      number: field('Number'),
      summary: field('Summary'),
      writer: field('Writer'),
      // Penciller is the usual credit; single-artist books sometimes only
      // fill Inker or CoverArtist.
      artist: field('Penciller') ?? field('Inker') ?? field('CoverArtist'),
      publisher: field('Publisher'),
      // ComicRack writes -1 for "unknown".
      year: year == null || year.startsWith('-') ? null : year,
      genres: (field('Genre') ?? '')
          .split(',')
          .map((g) => g.trim())
          .where((g) => g.isNotEmpty)
          .toList(),
    );
  }

  /// "Writer · Artist", skipping whichever is missing or a repeat.
  String? get credits {
    final names = {?writer, ?artist};
    return names.isEmpty ? null : names.join(' · ');
  }
}

bool isComicInfoPath(String path) =>
    path.split(RegExp(r'[/\\]')).last.toLowerCase() == 'comicinfo.xml';
