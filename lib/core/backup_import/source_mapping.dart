/// Paperback scraper-site id -> the display name of its Suwayomi
/// equivalent extension, if one exists. Resolved against whichever
/// sources are actually installed at import time (never a hardcoded
/// numeric source id, which is instance-specific) - see
/// `BackupImportController._resolveSourceIds`.
///
/// `null` means genuinely no Suwayomi equivalent is known (adult/doujin
/// sites, retired scrapers, etc.) - those titles surface as
/// NO_MAPPABLE_SOURCE rather than being silently dropped.
const Map<String, String?> paperbackToSuwayomiSourceName = {
  'MangaBat': 'Mangabat',
  'Mangakakalot': 'Mangakakalot',
  'MangakakalotGG': 'Mangakakalot',
  'MangaKakalotGG': 'Mangakakalot',
  'Manganato': 'Manganato',
  'MangaBuddy': 'ManhwaBuddy',
  'AsuraScans': 'Asura Scans',
  'BatCave': null,
  'ReadComicsOnline': 'Read Comics Online',
  'ReadComicOnline': 'Read Comics Online',
  'MangaDex': 'MangaDex',
  'NHentai': null,
  'Atsumaru': null,
  'MangaKatana': 'MangaKatana',
  'BatoTo': null,
  'ToonilyMe': 'Toonily.me',
  'KissManga': 'Kissmanga.in',
  'MangaXYZ': null,
  'MangaForest': null,
  'MangaMad': null,
  'UToon': null,
  'TooniTube': null,
  'MangaReaderTo': null,
  'FlameScans': null,
  'FlameComics': 'Flame Comics',
  'Hentai20': null,
  'AllPornComic': null,
  'ComicK': null,
  'ReadAllComics': null,
  'Paperback': null,
};
