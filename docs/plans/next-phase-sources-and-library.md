# Next phase: sources, covers, updates, filters, backup

Status: **awaiting approval (Gate 1)**. Researched 2026-10-26 against the live
Suwayomi (v2.4.2366 Stable), the app code on `claude/manga-brand-game`, and
Netsky's Paperback repos.

Decisions taken with the owner:

| Question | Decision |
|---|---|
| Extra sources per series | Linked backups with automatic fallback; main source can be switched |
| Who sees a refreshed cover | Everyone; only the owner can change it; stored on the server |
| How to get more sources | Suwayomi extension repos (Tachiyomi/Mihon format). No Paperback runtime |
| "Filters based on preference" | All three: saved presets, standing content preferences, each source's own filters |

## What already exists (reuse, don't rebuild)

- **Migrate to another source**: `SuwayomiBackend.migrate` and
  `features/collections/migrate_sheet.dart`. It is only reachable from a
  collection's long-press menu, not from the series page.
- **Cross-source title search**: `migrate_sheet.dart` searches every installed
  `en`/`all` source 6 at a time. `searchSourceCatalog`, `browseSource`,
  `mangaPreview` and `chapterSummary` are on the backend.
- **Chapter number mapping**: `fetchChapterIdsByNumber`, `markChaptersRead`.
- **Extension health**: `SuwayomiMaintenanceClient` (a fixed list of 14
  packages, reinstall, Suwayomi `.tachibk` backup/restore). The owner-only
  maintenance screen is `features/suwayomi/suwayomi_maintenance_screen.dart`.
- **ComicVine lookup** for imported comics (`comicvine_match_sheet.dart`).
- **New-chapter detection**: `newChaptersSince` in History, plus desktop-only
  notifications (`chapter_notification_scheduler.dart`) that poll
  `continueReading()`.
- **Owner role**: `isOwnerProvider`.
- **Local state**: about 20 Hive boxes. History, collections, reader
  settings, appearance, stats and connections already sync per account
  through `ResourceSync`.

## What Suwayomi's API offers that the app doesn't use yet

`addExtensionStore` / `removeExtensionStore` / `extensionStores`,
`installExternalExtension`, `updateExtension(s)` (install/update/uninstall),
`source { preferences filters isConfigurable iconUrl homeUrl }`,
`updateSourcePreference`, `fetchSourceManga(filters:)`, `updateLibrary`,
`libraryUpdateStatus`, `lastUpdateTimestamp`, manga `latestUploadedChapter`,
`latestFetchedChapter`, `unreadCount`, `setMangaMeta` / `meta`, trackers.

## Research findings

### Mangabat failures (item 7)

- Mangabat itself is the problem. `img-r2.2xstorage.com` returns HTTP 503 for
  some files (e.g. *Mount Hua* ch. 161, page 2) every time, whether requests
  are rapid or spaced out. The chapter page lists one CDN and no backups, so
  the Keiyoushi extension has nowhere to fall back to.
- Netsky's Paperback MangaBat source (`TheNetsky/mangabox-extensions`,
  `src/generic/`) reads the same image URLs from the HTML `<img>` tags, sends a
  `referer` of the site and the default user agent, and rate-limits to 5
  requests per 2 seconds. Nothing there routes around a file the CDN refuses
  to serve.
- Not tested: whether the same chapter loads in Paperback on your device. The
  sandbox blocked header-variation tests against the CDN, and I didn't work
  around that. **To compare, open *Return of the Mount Hua Sect* ch. 161 in
  Paperback.** If page 2 loads there, the difference is in request headers and
  is worth a closer look. If it fails there too, there's nothing to copy.
- What actually fixes this for readers is item 1 (fall back to another
  source) plus a sane retry/timeout on page loads.

### Paperback extensions (item 8)

- Paperback 0.9 extensions are TypeScript bundles built against
  `@paperback/types` 1.0.0-alpha. They call a global `Application` runtime
  (`scheduleRequest`, interceptors, cookie/state storage, Cloudflare bypass)
  that only exists inside the Paperback app.
- Running them on the server would mean reimplementing that runtime in Node
  and chasing an alpha API, which is why we're not doing it.
- Suwayomi's own repo support covers the need. Keiyoushi (already configured)
  ships Mangabat, Manganato, Mangakakalot and ReadComicsOnline, and other
  Tachiyomi-format repos can be added by URL.
- If a site has no extension in any repo, the fallback is to write a
  Tachiyomi-format extension (Kotlin) and install it with
  `installExternalExtension`. Netsky's TypeScript parsers are a readable
  reference for the selectors.

## Plan

One branch per item, each merged on its own. Every UI task ends with
`/impeccable:impeccable critique` and `/design-taste-frontend`, a check at
phone, 1101×688 and 688×1101, an install on the tablet, then
`flutter analyze` and `flutter test`.

### Item 8: Extensions and sources (High)

Owner: **Settings → Sources & extensions**. This replaces the fixed 14-package
health list but keeps the "reinstall missing" action.

1. `SuwayomiMaintenanceClient`: list/add/remove extension repos
   (validate the URL; reject non-https); list extensions with install, update
   and obsolete state, version and repo; install/update/uninstall;
   update-all.
2. A source details page (owner and users): icon, name, language, version,
   repo, home URL, supports-latest, and a live health check (search
   "a" plus one chapter page, with a timing). The owner sees the source's
   preferences rendered from `ListPreference` / `SwitchPreference` /
   `EditTextPreference` / `MultiSelectListPreference` and saved through
   `updateSourcePreference`. Users see them read-only.
3. Users: hide a source from search and discovery (stored per account through
   `ResourceSync`; nothing changes on the server).
4. Pin Mangabat and ReadComicsOnline at the top of the list and show their
   health on the maintenance screen.
5. Separately, on the server (not app code): clean up the duplicate stale
   jars (3 × asurascans, 3 × kissmangain, and others) after confirming which
   one is loaded.

Tests: the client against a mocked GraphQL (`http_mock_adapter`), preference
parsing for every preference type, repo URL validation, and the hidden-source
filter.

### Item 1: Linked sources with automatic fallback (High)

Suwayomi series only. Komga series are files on disk and have no sources.

- **Storage**: on the main series, Suwayomi manga meta
  `shaddai.linkedSources` = JSON list of manga ids (shared, server-side). A
  linked series is fetched but **not** added to the library, so the Library
  shows no duplicates.
- **UI**: series menu → "Sources" sheet. It lists the main source and the
  linked ones (chapter count, newest chapter, last health), plus "Add a source"
  (reuses the migrate sheet's search) and "Make main" (reuses `migrate`).
- **Fallback**: in `PageCache.getPage`, a page load first gets a 20 s timeout
  and one retry; that fixes the endless spinner. If it still fails on a
  Suwayomi chapter, ask the backend for the same chapter number on each linked
  source in order. The whole chapter switches over, because page counts differ
  between sources. A slim banner in the reader says "Reading from Manganato —
  Mangabat couldn't load this chapter".
- **Progress**: written to the main series' chapter by chapter number, so
  Continue reading and History don't fork.
- **Downloads** use the same fallback.

Tests: chapter-number matching including decimals (10.5) and missing numbers,
fallback order, timeout/retry, progress written to the main chapter, and no
fallback for Komga/local.

### Item 2: Refresh cover and metadata (High, owner only)

- Series menu → "Refresh cover & details". The sheet shows candidate covers
  side by side with their size:
  - **AniList GraphQL** (no key): `coverImage.extraLarge` and `bannerImage`
    (wide; used as the series page backdrop/wallpaper), plus description,
    genres, status and alt titles. Used for manga and manhwa.
  - **MangaDex** covers API: original-resolution covers per volume.
  - **ComicVine** (key already stored) for comics.
  - The source's own cover after a fresh `fetchManga`.
- **Saving**:
  - Komga: upload through Komga's series thumbnail API and mark it selected.
    Metadata goes through PATCH series metadata, with the fields locked so a
    rescan doesn't revert them.
  - Suwayomi has no cover upload. Store `shaddai.cover` / `shaddai.banner`
    URLs and metadata overrides in manga meta, and have
    `thumbnailUrlForSeries` / `getSeries` honour them. Other Suwayomi clients
    (its web UI) won't see these. That's an accepted limitation.
- Match by title with year and alt titles. The owner always confirms; nothing
  is auto-applied.

Tests: AniList/MangaDex parsing from recorded fixtures, title matching, meta
override precedence, and owner-only visibility.

### Item 3: Quick search from the series menu

- Series menu → "Search for this title". It opens the existing search
  (`/search`) prefilled with the title and alt titles, on the "Sources" tab,
  so the result can be added, linked as a backup (item 1) or migrated to.
- Small: an `initialQuery` parameter on the search screen and one `_Action`
  in `SeriesActionsSheet`.

Tests: a widget test that the action pushes search with the query.

### Item 4: Updates

- A new **Updates** section: a strip on Home and a full screen. It lists new
  chapters for series you are reading or have finished, newest first,
  grouped by day, with unread dots.
  - Suwayomi: chapters ordered by `fetchedAt` for library manga that have
    read chapters.
  - Komga: `recentlyAdded()` books filtered to series in History.
- "Check for updates": owner triggers `updateLibrary` and the screen shows
  `libraryUpdateStatus` progress. Everyone gets pull-to-refresh, which re-reads.
- Show "Last checked 2 h ago" (`lastUpdateTimestamp`).
- Desktop notifications keep working. Mobile push stays out of scope for now
  (it needs a background-fetch plugin); add it when asked.

Tests: grouping and filtering ("read or reading only"), and Komga/Suwayomi
merge ordering.

### Item 5: Search filters and preferences

- **Source filters**: render a source's `filters` (Select, Checkbox, TriState,
  Group, Sort, Text) in a filter sheet and pass them to `fetchSourceManga`.
- **Content preferences** (per account, synced): hidden genres, adult content
  off by default, languages, and content types (comics / manga / manhwa).
  These apply to search, browse, recommendations and updates.
- **Saved presets**: name and save the current filter set, and reapply it in
  one tap (per account, synced).
- Library search gets genre, status and unread filters on top of the
  existing text search.

Tests: filter serialization round-trip for every filter type, the preference
filter, and preset save/load.

### Item 6: Backup and restore on device (per user)

- Settings → "Back up to this device" writes `shaddai-<user>-<date>.json`
  through `file_picker` save (on web, a download). It contains history,
  collections, reader settings, appearance, stats, stopped series, chapter
  watch, servers (**without passwords or tokens**), source preferences, linked
  sources view, content preferences and filter presets. It includes a schema
  version and the account name.
- "Restore" shows a preview of what's in the file and asks merge or replace.
  It warns when the file belongs to another account, and syncs after restoring.
- Never uploaded anywhere.

Tests: round-trip export → wipe → import, merging, rejecting a newer
schema version, and that secrets are absent from the file.

### Item 7: Paperback study (Low)

Done above. What's left is the one comparison on your device. If page 2 of
ch. 161 loads in Paperback, I'll look at what its request does differently.

## Order and size

| # | Item | Size | Depends on |
|---|---|---|---|
| 1 | 8 Extensions & sources | L | — |
| 2 | 1 Linked sources + fallback | L | 8 (source list, health) |
| 3 | 3 Quick search | S | — (links into 1) |
| 4 | 2 Covers & metadata | M | — |
| 5 | 4 Updates | M | — |
| 6 | 5 Filters & preferences | M | 8 (hidden sources) |
| 7 | 6 Backup & restore | M | after 1, 5 (new stores to include) |

## Risks

- **Suwayomi meta is shared**: linked sources and cover overrides are visible
  to every app user, which is intended. Keys get a `shaddai.` prefix so they
  don't collide with other clients.
- **Source preferences change server behaviour for everyone**, so only the
  owner can edit them.
- **Third-party repos run code on the server.** Adding a repo is owner-only,
  with a warning that names the repo's signing key.
- **Fallback could mask a broken main source**: the source health shown in
  the Sources sheet keeps that visible.
- **Rate limits**: the cross-source search keeps the existing 6-at-a-time cap.
  Health checks run on demand, never on a timer.
