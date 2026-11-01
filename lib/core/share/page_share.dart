/// What goes out with shared pages, so a WhatsApp group sees which title,
/// chapter and source a screenshot came from and can open it themselves.
library;

/// The web reader. Hash routes, so a title opens at `/#/series/<id>` for
/// anyone signed in; others land on the sign-in page.
const shaddaiWebUrl = 'https://reader.shaddaicommunications.com';

/// A source's address for a title or chapter. Suwayomi stores most paths
/// relative to the source's base address ("/series/x/chapter/45"); some
/// sources store the whole address. Null when neither gives one.
String? sourceUrl(String? baseUrl, String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  if (baseUrl == null || baseUrl.isEmpty) return null;
  final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
  final rest = path.replaceAll(RegExp(r'^/+'), '');
  return '$base/$rest';
}

/// The text that travels with the pages:
///
///     Chronicles Of The Demon Faction
///     Ch. 190 · Asura Scans (EN) · p. 8, 9
///     Read it: https://asurascans.com/…/chapter/190
///     In Shaddai Reader: https://reader.shaddaicommunications.com/#/series/1
///
/// [pages] are 0-based indices; shown 1-based. Lines without a value are
/// left out.
String shareCaption({
  required String title,
  required String chapter,
  String? source,
  List<int> pages = const [],
  String? sourceLink,
  String? appLink,
}) {
  final sorted = [...pages]..sort();
  final where = [
    chapter,
    ?source,
    if (sorted.isNotEmpty)
      '${sorted.length == 1 ? 'p.' : 'pp.'} ${sorted.map((p) => p + 1).join(', ')}',
  ].join(' · ');
  return [
    title,
    where,
    if (sourceLink != null) 'Read it: $sourceLink',
    if (appLink != null) 'In Shaddai Reader: $appLink',
  ].join('\n');
}

/// The Shaddai web reader's page for a title.
String appLinkForSeries(String seriesId) =>
    '$shaddaiWebUrl/#/series/${Uri.encodeComponent(seriesId)}';
