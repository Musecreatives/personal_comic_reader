# Changelog

## Phase 5 — OPDS backend, stats, smart panel view, wide layout, iOS prep

- **`OpdsBackend`** (`lib/backends/opds/`): a fifth `ReaderBackend`,
  generic OPDS 1.2 + OPDS-PSE over any catalog, not just Komga's. A
  `Library` is whatever top-level navigation entries the root catalog
  exposes; a `Series` is a subsection entry one level in; a `Book` is an
  entry with either a PSE stream link (`pse:count` + a `{pageNumber}`
  href template) or a plain acquisition link. Page streaming prefers PSE;
  when a book has none, the whole acquisition file is downloaded once and
  unzipped in-app via `package:archive` (CBZ fallback, web-safe - no
  native unzip dependency), with pages cached in memory per book.
  Book/series identity is feed-URL-based (OPDS has no stable numeric
  IDs), cached internally as `listSeries`/`listBooks` encounter entries -
  same tradeoff already made for Kavita's and Suwayomi's location
  caches. Verified end-to-end against the live Komga OPDS catalog (root
  feed → "All libraries" → "Comics"/"Manga" library feeds all parse and
  render correctly); PSE and the CBZ fallback are unit-tested against
  synthetic feeds/zips since no currently-populated OPDS server was
  available to verify page streaming against real content.
- **Reading stats** (`lib/core/stats/`, `lib/features/stats/`): local-
  only per-day page/time tracking, a streak counter, and a weekly
  fl_chart bar chart, with a toggle to disable (record calls become a
  no-op). Wired into the reader: a page counts once per book session
  (deduped via a seen-pages set, so re-scrolling doesn't inflate the
  count) and reading time is recorded on dispose. Reachable from a new
  bar-chart icon on Home.
- **Smart panel view** (experimental): `lib/core/panels/panel_detector.dart`
  finds gutters via row/column *luminance variance* (not a fixed
  white/black threshold - a solid-color panel would otherwise be
  indistinguishable from a gutter) to split a page into a reading-order
  grid of panels. `PanelZoomView` animates between them using the same
  `BoxFit.contain` placement math for both the crop rectangle and the
  actual paint, so they agree pixel-for-pixel. Deliberately isolated
  from the normal pager widgets: it's a same-page overlay activated via
  a button in the reader overlay (single-page mode only), not a rewrite
  of `SinglePageView`. Tested via a pure-geometry function fed synthetic
  RGBA buffers (checkerboard panels, not solid color - solid rectangles
  have zero internal variance in every direction and would be
  indistinguishable from a gutter to this detector, which the test
  fixture had to account for).
- **iPad/wide layout**: `LibraryScreen` grows a persistent sidebar
  (every library) next to the series grid at ≥800px width, so switching
  libraries doesn't need a round trip back through Home. Library
  selection is in-place state, not a new route push.
- **iOS prep**: bundle ID changed to `home.shaddai.reader` (was
  `home.shaddai.shaddaiReader`) across the Xcode project;
  `NSLocalNetworkUsageDescription` and an `NSAppTransportSecurity`
  arbitrary-loads exception added to Info.plist (self-hosted servers are
  plain HTTP on a private network, not public HTTPS domains ATS's
  per-domain exceptions are designed for); `codemagic.yaml` with a
  TestFlight-publishing workflow (placeholders - needs a real App Store
  Connect API key configured in Codemagic itself) and an unsigned-build
  sanity-check workflow. None of this could be executed locally (no Mac/
  Xcode toolchain in this environment) - it's configuration, not a
  verified build.
- Tests: `OpdsBackend` (navigation/series/book mapping, PSE URL
  substitution, CBZ download+unzip+sort, the unseen-book-id error path),
  `ReadingStatsStore` (accumulation, disabled-is-a-no-op, `lastDays`
  ordering, streak counting including the gap and today-not-required-yet
  cases), `panelsFromRgba` (grid splitting, rtl reversal, whole-page
  fallback), and a new wide-layout sidebar test for `LibraryScreen`. 64
  tests total, all passing; `flutter analyze` clean.

### A real bug found and fixed during manual verification

Every `context.push('/library/${lib.id}')`-style navigation call used
the entity ID as a raw path segment. That's fine for Komga/Kavita/
Suwayomi's plain string/numeric IDs, but `OpdsBackend`'s IDs are full
feed URLs containing literal slashes and colons - tapping "All
libraries" threw `GoException: no routes for location:
/library/http://100.108.109.63:8081/opds/v1.2/libraries`, since
go_router's `/library/:id` pattern matches exactly one path segment.
Fixed by `Uri.encodeComponent`-ing every entity ID at every navigation
call site (`home_screen.dart`, `library_screen.dart`, `series_screen.dart`,
`reader_screen.dart`); go_router decodes `pathParameters` back
automatically, so no change was needed on the receiving end in
`router.dart`. This is a no-op for the other three backends' plain IDs,
so nothing about their behavior changed - confirmed by the full test
suite and by re-driving Komga/Kavita/Suwayomi navigation manually after
the fix. Found by actually clicking through the live Komga OPDS catalog
rather than trusting the unit tests' synthetic feeds alone, which is
exactly the kind of thing synthetic feeds can't catch (they never
happen to contain a URL as an "id").

### Manual verification

- OPDS: added a real server against `http://100.108.109.63:8081/opds/v1.2/catalog`
  with real Komga credentials - "Connected successfully", then full
  navigation from Home through "All libraries" to the Comics/Manga
  library tiles, all against live server responses (not mocks).
- Stats and the OPDS server-type option both render correctly in the UI
  (screenshots via the same headless-Edge/release-build setup used in
  every prior phase).
- iOS changes are configuration-only and unverified beyond visual
  inspection of the modified files - there's no Mac in this environment
  to actually run `flutter build ios --no-codesign` or exercise
  Codemagic. Flagged explicitly rather than claimed as tested.

## Phase 4 — Offline downloads + Caddy hosting

- **Download queue** (`lib/core/downloads/`): `DownloadManager` runs up
  to 2 books downloading at once, pulling from a Hive-persisted queue
  (`DownloadStore`). Pause/resume/cancel just flip queue state; the pump
  loop picks up the next queued task whenever a slot frees. Wi-Fi-only
  mode (checked via `connectivity_plus` before each page, no-op on web
  per the original spec) pauses a task rather than failing it when it's
  on cellular. Downloaded page bytes live in their own Hive box, kept
  separate from the reader's opportunistic LRU/disk cache - a deliberate
  download should survive an app restart and never get silently evicted
  the way a "just read recently" page can.
- **Offline-first page resolution**: `PageCache.getPage()` now checks
  the download store before its own cache or the network. The reader
  doesn't need to know or care whether a page came from a download or a
  live fetch.
- **Download UI**: a download button per book (and one for the whole
  series) on the series screen, with a live state icon (spinner/done/
  paused/error) driven by a `StreamProvider` over `DownloadManager`'s
  change notifications; a Downloads screen (queue, pause/resume/cancel,
  Wi-Fi-only toggle); a Storage screen (total size, size per series,
  clear one series / all downloads / the opportunistic page cache, plus
  a Safari storage-eviction warning on web).
- **PWA hardening**:
  - `ConnectivityBanner` (`lib/app/connectivity_banner.dart`) shows a
    slim "offline - showing downloaded content" banner and flushes the
    progress-sync queue the moment connectivity returns.
  - `LastRouteStore` persists the current route (skipping the reader and
    any add/edit form, which can't safely replay without their original
    state) so a cold start - especially while offline - reopens where
    you left off instead of always landing on Home. `router.dart`'s
    `appRouter` constant became `buildRouter({initialLocation,
    onRouteChange})` to make this possible; `main.dart` now constructs
    the router after reading the saved route.
  - Flutter's own release-build service worker already caches the app
    shell precache-first; no custom service worker was needed on top of
    that for this phase.
- **Same-origin defaults**: when the app detects it's being served from
  `reader.shaddai.home` (`Uri.base.host`), a new Komga/Kavita server's
  URL field defaults to `/komga` or `/kavita` off that same origin -
  side-stepping the CORS block a bare Tailscale IP always hits from a
  browser (see Phase 2/3). Direct-IP entry still works for local dev.
- **`deploy/`**: `build.ps1` (builds the release bundle and `scp`s it to
  the Caddy host), `Caddyfile.snippet` (serves the app at
  `reader.shaddai.home` and reverse-proxies `/komga` + `/kavita`
  same-origin), and a full manual-steps writeup in `README.md`
  (bind-mount, Caddyfile append + reload, AdGuard DNS rewrite, iOS Add
  to Home Screen).
- Tests: `DownloadManager` (full download to completion, pause mid-flight
  then resume to completion, cancel clears task + pages, re-enqueueing an
  already-downloaded book doesn't re-fetch) and offline-first page
  resolution (a downloaded page is returned without the backend ever
  being called, a missing download correctly falls through to the
  network, a downloaded page wins over a *different* page already
  sitting in the opportunistic cache). 45 tests total, all passing;
  `flutter analyze` clean.

### Manual verification

Downloaded a real chapter (21 pages) from the live Suwayomi instance
through the actual UI: watched the per-book spinner progress, confirmed
the Downloads screen showed live "N / 21 pages - running" progress,
paused it mid-download (stopped cleanly at 4/21, no further network
calls after pause), and confirmed the Storage screen reported the
correct real size (2.5 MB) and series grouping. All against
`http://100.108.109.63:4567` via the same headless-Edge / release-build
setup used in Phases 2-3.

## Phase 3 — Kavita backend, Suwayomi backend, Kapowarr status view

Scope expanded mid-phase at the user's request: Suwayomi (Tachidesk) is
now a full fourth `ReaderBackend`, and Kapowarr gets a lightweight,
read-only status view (not a backend - it's an acquisition tool, not a
source of readable content).

- **`KavitaBackend`** (`lib/backends/kavita/kavita_backend.dart`): real
  implementation replacing the Phase 1 stub. JWT login via
  `/api/Account/login`, lazy auth (first request triggers login) with
  automatic re-login on a 401, `Series`/`Chapter` mapped from
  `/api/Series/all-v2`, `/api/Series/volumes`, `/api/Chapter`. Progress
  updates require Kavita's full `ProgressDto` (chapterId, pageNum,
  seriesId, volumeId, libraryId), so the backend caches chapter→series
  and series→library lookups as it encounters them, backfilling with an
  extra request only on a cache miss. Verified against a live instance
  for auth, routing, the `Pagination` response header shape, and error
  responses; the account had zero series indexed in any library, so
  populated-response field names are best-effort from Kavita's known API
  conventions rather than confirmed against real content - worth a
  revisit once the library has something scanned in. The `all-v2` filter
  DTO shape specifically wasn't verified, so `listSeries` fetches
  unfiltered pages and filters library/unread/search client-side rather
  than risk a malformed filter silently returning nothing.
- **`SuwayomiBackend`** (`lib/backends/suwayomi/suwayomi_backend.dart`):
  GraphQL implementation against `/api/graphql`. No login required (runs
  open on the Tailscale network). Maps a `Library` to a Suwayomi
  Category, a `Series` to a Manga, and a `Book` to a Chapter. Page bytes
  require calling the `fetchChapterPages` mutation first (Suwayomi
  fetches a chapter's page list from its source lazily, hence
  `pageCount: -1` until then) before hitting the predictable
  `/api/v1/manga/{id}/chapter/{id}/page/{n}` REST route. Verified
  end-to-end against a live instance with real content (see Manual
  verification below) - this is the most confidently-tested of the four
  backends. Collections and reading lists return empty lists; Suwayomi
  has no concept distinct from categories, which are already used as
  libraries.
- Server type selector (`ServerEditScreen`) now offers Komga/Kavita/
  Suwayomi; username/password are optional (and labeled as such) when
  Suwayomi is selected, since it needs neither.
- **Kapowarr status view** (`lib/core/kapowarr/`,
  `lib/features/kapowarr/`): a separate, minimal connection (URL + API
  key, not folded into the server list) with a read-only screen showing
  volume/issue/file stats, the current download queue, and recent
  download history. Shaddai Reader never triggers downloads or edits
  volumes through this - it's a status mirror, not a Kapowarr client.
  Reachable from Settings.
- `series_screen.dart`'s book-list `FutureBuilder` now surfaces errors
  instead of spinning forever on failure - found via a real bug (see
  below) where it was silently masking a broken Suwayomi query.
- Tests: `KavitaBackend` (lazy login + bearer header, library/series
  mapping, the full progress DTO round-trip via the location-cache
  lookup) and `SuwayomiBackend` (category/manga/chapter mapping,
  progress mutation) against mocked dio, plus `KapowarrClient` (stats/
  queue/history parsing, including the `file_title` fallback when
  `web_title` is absent). 46 tests total, all passing; `flutter analyze`
  clean.

### A real bug found and fixed during manual verification

`SuwayomiBackend.listBooks()` originally queried
`manga(id) { chapters(orderBy: SOURCE_ORDER) { ... } }`, but Suwayomi's
`Manga.chapters` field takes **no arguments at all** - confirmed via
GraphQL introspection after the fact. The invalid argument made every
`listBooks()` call return a GraphQL error, which `series_screen.dart`'s
`FutureBuilder` silently swallowed into an infinite loading spinner
(only visible as a generic unhandled-JS-error in the browser console,
not surfaced in the UI). Fixed by dropping the argument - the result
list is already sorted client-side by chapter number afterward, so
server-side ordering wasn't load-bearing. This is exactly the kind of
mismatch the "verified against a live instance" claims below are meant
to catch; it shipped once, and the fix for *why* it went unnoticed
(the swallowed-error FutureBuilder) is arguably more important than the
one-line GraphQL fix itself.

### Manual verification

Full round trip against real, populated content - not just empty-state
checks like Phase 1/2:
- Added Komga, Kavita, and Suwayomi servers through the actual UI
  against their live Tailscale addresses; all three reported "Connected
  successfully."
- Switched active server to Suwayomi, browsed Home → Library (Default
  category) → "Chronicles of the Demon Faction" (real manga, real
  cover, real synopsis, "0/184 read") → Chapter 1 → **the actual reader
  screen**, with real page images loading, a real page count (22, not
  the placeholder -1), the Panels-style overlay showing "Chapter 1 /
  Vol/Ch 1", and a working page slider. This is the first time the
  reader has been verified against real content end-to-end.
- Kapowarr: connected with the API key, "Connected - 4 volumes
  tracked." on test, then the status screen rendered real stats (4
  volumes, 34 issues, 164.9 MB), an empty download queue, and real
  history entries ("One World Under Doom #6 (2025) • 45m ago").
- Kavita: connected successfully and reached the empty-library screen
  without error (still nothing scanned into that instance - see the
  KavitaBackend note above for what that means for field-mapping
  confidence).
- All of the above via a headless Edge (`playwright-core`, no
  `chromium-cli` in this environment) against a `flutter build web
  --release` bundle - the debug `flutter run -d web-server` target hung
  indefinitely in this environment (noted in Phase 2), so release builds
  are the reliable path for this kind of check here.

## Phase 2 — Reader core + progress sync

- Reader settings model (`lib/core/reader/reader_settings.dart`): mode
  (single/double/vertical continuous), direction (ltr/rtl), fit
  (width/height/screen/original), double-page cover-alone + offset,
  tap zones, keep-screen-on, background color, page gap, upscale,
  brightness, color filter. Persisted in Hive via
  `ReaderSettingsStore` as a global default plus an optional
  per-series override ("remember these settings").
- `PageCache`: in-memory LRU (12 pages) + Hive disk cache for page
  bytes, with fire-and-forget prefetch of the next few pages as the
  reader advances.
- `ProgressSync`: debounces `updateProgress` calls by 1s, collapsing
  rapid page changes into one request; failed sends are queued in
  Hive and retried on the next successful call or flush.
- Reader screen at `/read/:bookId?page=n`
  (`lib/features/reader/reader_screen.dart`), wired up from the
  series book list (tapping a book now opens the reader instead of
  the Phase 1 placeholder snackbar):
  - **Single-page mode**: `PageView` with pinch zoom and double-tap
    zoom-to-point via `InteractiveViewer`; page-turn swipes are
    disabled while zoomed so panning takes over.
  - **Double-page mode**: pages paired into spreads honoring
    direction, cover-alone, and offset (`lib/core/reader/spread_logic.dart`,
    pure and unit-tested); landscape pages (aspect ratio > 1.15,
    detected from decoded image dimensions) are never paired and get
    their own spread, with the spread list reflowing live as
    dimensions become known.
  - **Vertical continuous mode**: fixed-extent `ListView` for
    reliable programmatic scroll/seek, wrapped in an `InteractiveViewer`
    for whole-list pinch zoom, with scroll position mapped back to a
    "current page" for progress tracking.
  - Tap zones (left third / right third / center), RTL-aware on all
    three axes: swipe direction, tap-zone-to-navigation mapping, and
    the page slider (`displayPositionForPage`/`pageForDisplayPosition`
    in `spread_logic.dart`, unit-tested for both directions).
  - Panels-style overlay: blurred translucent top/bottom bars that
    fade in/out on center tap, with a page slider, mode/direction
    toggle buttons, and a settings icon. Slide-up settings sheet
    covers every `ReaderSettings` field plus the remember-for-series
    toggle.
  - End-of-book card: "Next: `<title>`" / "Back to series" / "Keep
    reading", auto-derived from the series' book order.
  - Keyboard arrow-key navigation (web), `wakelock_plus` tied to the
    keep-screen-on setting, per-page error state with a retry button
    that doesn't take down the rest of the reader.
- Tests: spread pairing (cover-alone, no-cover-alone, odd trailing
  page, offset, landscape exclusion, empty book), spread display
  order (ltr/rtl/single-page), RTL slider position mapping
  (including round-trip inverse), and progress-sync debounce/queue/
  flush behavior against a fake backend. 41 tests total, all passing;
  `flutter analyze` clean.

### Manual verification

- `flutter build web --release` served statically and driven with a
  headless Edge (via `playwright-core`, since `chromium-cli` wasn't
  available in this environment): empty state, add-server form, and
  the post-save library list all render correctly against a live
  Komga server over Tailscale with zero console errors.
- Talking to the Tailscale IP directly from a browser hits CORS
  (Komga sends no `Access-Control-Allow-Origin`) - expected per the
  project's own Phase 4 plan to proxy same-origin in production; the
  manual check above used `--disable-web-security` in a throwaway
  profile to see past it for verification only.
- Could not visually verify the reader screen itself end-to-end: the
  connected Komga account has 0 series across every library
  (confirmed directly via `curl` - `totalElements: 0`), so there was
  no book to open. The series/book list screens correctly render
  their empty state rather than erroring. Re-verify once the Komga
  libraries actually have content scanned in.

### Performance notes

- Debug-mode `flutter run -d web-server` hung indefinitely on first
  load in this environment (DWDS/DDC boot never completed, likely
  because the Dart Debug Chrome extension isn't installed here) -
  release builds loaded normally. Not expected to affect a normal
  `flutter run -d chrome` workflow, which use the debug extension
  path Chrome installs automatically; worth a quick check if a
  similar hang shows up there.

## Phase 1 — Scaffold, backend adapter, Komga auth + library browse

- Project scaffolded for web + iOS targets (Windows dev machine, no iOS
  toolchain here — iOS build deferred to Codemagic/Mac per project
  context).
- `ReaderBackend` abstract interface defined in `lib/core/backend/`,
  covering auth, libraries, series, books, pages, progress, continue
  reading, recently added, collections, and read lists.
- `KomgaBackend` implemented against the live Komga REST v1 API
  (endpoints and response shapes verified against a running instance
  at `100.108.109.63:8081`, not guessed from docs).
- `KavitaBackend` stub — throws `BackendNotImplemented` on every method;
  exists so the server-type selector works without crashing. Real
  implementation is Phase 3.
- Server management: add/edit/delete servers, test-connection button,
  select active server. Configs in Hive, passwords in
  `flutter_secure_storage` (web-safe via its bundled IndexedDB/WebCrypto
  backend — no shared_preferences fallback needed).
- Screens: `/home` (continue reading + recently added rows, library
  shortcuts), `/library/:id` (paginated series grid/list, sort, search,
  unread filter), `/series/:id` (cover, summary, book list with
  progress), `/settings`, `/settings/servers`.
- Dark theme by default; wide-screen two-column layout on series detail.
- `RetryInterceptor` added to dio: retries 5xx/timeout/connection errors
  up to twice with backoff; never retries 4xx.
- Tests: `KomgaBackend` unit tests against a mocked dio adapter
  (auth success/failure, library/series parsing incl. the Spring
  Pageable envelope and title fallback, progress update, thumbnail URL
  building) and a widget test asserting the library grid renders one
  tile per series with correct unread badges.
- PWA manifest and `index.html` updated with the app's actual name,
  description, and dark theme color (icons still placeholders — no
  branding art yet).

### Known Komga API field mismatches vs. the original plan

None found — every endpoint listed in the Phase 1 prompt (`/api/v1/series/list`,
`/api/v1/books/ondeck`, `/api/v1/books/latest`, `/api/v1/books/{id}/pages/{n}`,
`/api/v1/books/{id}/read-progress`, thumbnail routes) was verified against
the live OpenAPI spec and matches exactly.

### Stubbed / deferred

- Kavita backend (Phase 3).
- Reader screen itself — `/series/:id` book taps currently show a
  placeholder snackbar (Phase 2).
- Collections/read lists have data-layer support but no dedicated
  screens yet (Phase 3 per the original plan).
