import 'reader_settings.dart';

/// Groups page indices (0-based, in reading order) into spreads of one or
/// two pages for double-page mode.
///
/// - [coverAlone]: page 0 is always its own spread (typical for a cover).
/// - [offset]: after the optional cover, skip this many additional pages as
///   singles before pairing starts - lets the user correct scans that are
///   off by one.
/// - [isLandscape]: pages this reports true for are never paired; they get
///   their own spread even if that leaves the next page unpaired too.
///
/// Direction does not affect grouping, only how a spread is displayed left
/// to right - see [spreadDisplayOrder].
List<List<int>> buildSpreads({
  required int pageCount,
  bool coverAlone = true,
  int offset = 0,
  bool Function(int pageIndex)? isLandscape,
}) {
  if (pageCount <= 0) return [];
  final landscape = isLandscape ?? (_) => false;
  final spreads = <List<int>>[];
  int i = 0;

  if (coverAlone) {
    spreads.add([0]);
    i = 1;
  }

  final skip = offset.clamp(0, pageCount - i);
  for (var j = 0; j < skip && i < pageCount; j++) {
    spreads.add([i]);
    i++;
  }

  while (i < pageCount) {
    if (landscape(i)) {
      spreads.add([i]);
      i += 1;
      continue;
    }
    if (i + 1 < pageCount && !landscape(i + 1)) {
      spreads.add([i, i + 1]);
      i += 2;
    } else {
      spreads.add([i]);
      i += 1;
    }
  }

  return spreads;
}

/// Left-to-right screen order for a spread's page indices, given [direction].
/// Single-page spreads are returned unchanged.
List<int> spreadDisplayOrder(List<int> spread, ReadingDirection direction) {
  if (spread.length < 2) return spread;
  return direction == ReadingDirection.ltr ? spread : spread.reversed.toList();
}

/// Maps a page index to its left-to-right slider position. In RTL, page 0
/// (the "first" page read) sits at the right edge of the slider, not the
/// left.
int displayPositionForPage(
  int pageIndex,
  int totalPages,
  ReadingDirection direction,
) {
  if (direction == ReadingDirection.ltr) return pageIndex;
  return totalPages - 1 - pageIndex;
}

/// Inverse of [displayPositionForPage]: given a left-to-right slider
/// position, which page index does it represent.
int pageForDisplayPosition(
  int position,
  int totalPages,
  ReadingDirection direction,
) {
  if (direction == ReadingDirection.ltr) return position;
  return totalPages - 1 - position;
}
