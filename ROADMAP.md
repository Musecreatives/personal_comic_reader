# Shaddai Reader — Roadmap & Status

Living document: what's shipped, what's deployed, what's decided, what's
open. Updated as we go — this is the source of truth for "what's next,"
not the CHANGELOG (which is a historical record per-phase and shouldn't
be edited after the fact).

## Status: all 5 original phases shipped and deployed

Full build history is in `CHANGELOG.md`. Short version: reader (single/
double/vertical modes, zoom, offline downloads with a Wi-Fi-only queue),
four backends (Komga, Kavita, Suwayomi, generic OPDS 1.2+PSE), Kapowarr
status view, local reading stats, an experimental smart panel view, an
iPad/wide two-column library layout, and iOS build config (untested — no
Mac in this environment).

**Deployed and live** at `https://reader.shaddai.home` since 2026-08-24,
served by Caddy from `/home/server/docker/caddy/sites/reader/` on the
home server, same-origin-proxied to Komga/Kavita/Suwayomi via `/komga`,
`/kavita`, `/suwayomi`. Redeploy = `flutter build web --release
--base-href /` then `scp -r build/web/* server@100.108.109.63:/home/server/docker/caddy/sites/reader/`.

## Infrastructure fixes made along the way

These aren't Shaddai Reader code, but they came up doing the deploy and
are worth remembering:

- **AdGuard boot race** (fixed 2026-08-24): `adguardhome`'s compose file
  binds ports to the literal Tailscale IP, not `0.0.0.0`. If Docker
  starts it before `tailscaled` has actually assigned that IP,
  Docker silently publishes *none* of its ports (not just the failed
  one), and a plain `docker restart` doesn't fix it — only a full
  recreate does. Fixed with a systemd oneshot (`adguard-fixup.service`,
  installed on the server; source in `deploy/adguard-fixup.service` and
  `deploy/adguard-wait-and-recreate.sh`) that waits for the real IP on
  every boot, then force-recreates the container.
- **Caddy single-file bind-mount gotcha**: the Caddy compose service
  bind-mounts `./Caddyfile` as a single file. Editing it via `scp`
  (which replaces-via-rename) swaps the inode; the running container's
  mount stays attached to the *old* inode and `caddy reload` silently
  keeps serving stale config. Bit us once (the `/suwayomi` proxy path
  didn't show up until a full `docker compose up -d --force-recreate
  caddy`). Documented in `deploy/Caddyfile.snippet`. Either force-recreate
  the caddy container after every Caddyfile edit, or edit the file with
  something that rewrites in place instead of replacing it.
- **`/suwayomi` same-origin proxy** was missing from the original Phase 4
  deploy (only `/komga` and `/kavita` were wired up) — added
  2026-08-24, both on the live server and in `deploy/Caddyfile.snippet`
  for future fresh deploys. The app's same-origin URL defaults
  (`server_edit_screen.dart`) now cover all three.

## Parked decisions

- **CLU** (`allaboutduncan/comic-utils-web`, running at
  `100.108.109.63:5577`): **correction (2026-08-25)** — earlier note said
  "no JSON API," which was wrong; that was only checking the bare `/api`
  path. CLU's JS files (`clu-metadata.js`, `collection.js`, `reader.js`,
  etc.) reveal a real, fairly extensive internal API: `/api/browse`,
  `/api/browse-thumbnails`, `/api/continue-reading`, `/api/favorites/*`,
  `/api/reading-lists/*`, `/api/mark-comic-read`, `/api/reading-position`,
  `/api/read/`, metadata search/scan, and file operations (move, rename,
  crop, combine CBZ). It has its own reading-position tracking and a
  built-in reader — real overlap with Shaddai Reader's territory. Still
  undocumented/unofficial (no auth scheme confirmed, stability unknown),
  but "no API" is no longer the blocker it was thought to be.
  **Decision: still parked pending the UI/UX pass, but worth revisiting
  sooner given this.** Options on the table: give it a
  `clu.shaddai.home` Caddy entry and leave it standalone, embed it as a
  link/webview, wrap its API as a lightweight companion feature, or a
  full native rebuild in Shaddai Reader's own UI.
- **Komga vs. Kavita**: both stay configured, no consolidation planned
  right now.

## Active thread: Paperback → Suwayomi migration

Backup received and analyzed (`Paperback-Archive.24-08-2026.16-58-22.pas5`,
a zip of Realm-exported JSON — 292 library titles, 36,578 chapters with
full read/unread history, 30 source sites, 11 custom tabs). Dry-run
matching against Suwayomi is done and reviewed:

- **248 titles** matched high-confidence against an installed/installed-
  for-this Suwayomi source (8 extensions installed 2026-08-25: Mangabat,
  Mangakakalot, Manganato, Read Comics Online, Toonily.me, MangaKatana,
  Kissmanga.in, Flame Comics). MangaBuddy → "ManhwaBuddy" mapping is
  unconfirmed (same site renamed, or different site) - flagged, not yet
  verified.
- **37 titles** have no Suwayomi-source equivalent. Of those, **8 are
  user-excluded** (won't be migrated or acquired anywhere): Youngest
  Scion of the Mages, Absolute Martial Arts, The Chronicles of Heavenly
  Demon, A Wonderful New World, Childhood Friend of the Zenith, Avengers
  vs. X-Men: Infinite, World's Strongest Survivor, The Regressed
  Mercenary's Machinations. Of the remaining 29: **21 are Western comics**
  (BatCave source) with plausible Kapowarr/ComicVine matches - checked
  2026-08-25, 20 of 21 found strong year-matched candidates, 2 need a
  manual pick ("Green Lantern: Legacy...", bare "X-Men (2019)"). Nothing
  added to Kapowarr yet - queuing a download is a real action, waiting
  on explicit go-ahead. The other **8 are manhwa/manga/doujin from
  scan/doujin sites** (MangaForest, UToon, TooniTube, BatoTo,
  ReadAllComics, Atsumaru, NHentai) with no realistic acquisition path
  through either Kapowarr (ComicVine doesn't catalog these) or CLU (no
  acquisition capability at all) - flagged as genuinely unmigratable
  this way, not yet resolved.
- **Applied 2026-08-25**: 246 of the 248 matched titles were added to
  Suwayomi's library, the 11 Paperback tabs recreated as categories, and
  9,209 of 9,242 read chapters marked read (remaining ~33 are chapter-
  numbering mismatches between Paperback's chapter list and the current
  Suwayomi source listing - not investigated further, low-impact). The
  2 MangaBuddy-sourced titles were skipped (unconfirmed site mapping,
  still open).
- **Kapowarr comics - applied 2026-08-25**: all 20 non-excluded Western
  comics queued as monitored volumes (Kapowarr auto-searches/downloads
  on add). ComicVine has real per-title data quality issues worth
  knowing about for future imports: several titles had duplicate-looking
  volume entries (same title/year/publisher, different internal IDs -
  picked the first one each time, content should be identical) and one
  title ("Fall of the House of X") had a French/Panini translated
  edition ranked above the correct Marvel English one by a naive
  top-result match - caught and fixed before committing (see below).

**Process note for future imports**: Kapowarr adds a volume with
`monitor: true` and starts downloading *immediately*, synchronously, no
confirm step - a wrong `comicvine_id` becomes a wrong download on disk
within seconds, not just a wrong library entry. Hit this once here (a
Panini France translated edition of "Fall of the House of X" auto-
downloaded before the mismatch was caught) and once more on a
copy-paste ID mistake for "X-Men: Hellfire Gala" - both times fixed by
unmonitoring, deleting with `delete_folder=true`, and re-adding the
correct ID. Lesson: always resolve to the exact `comicvine_id` and
double check publisher/translated flags *before* the POST, not after.

Working files (source data, scripts, match reports) live in this
session's scratchpad, not the repo - nothing here is committed code yet.

## Next up: UI/UX pass + feature consolidation

Plan going in: prototype screens (web, tablet, phone) via Claude Design
before touching app code, then implement against the approved designs.
Scope not yet fixed — to be filled in as design work happens. Candidate
areas once we're in it:

- Whatever comes out of the Paperback import work (library merge UI,
  read-history reconciliation).
- CLU integration, once the parked decision above is revisited.
- Anything else that falls out of the design pass - this list grows as
  we go, not written in stone up front.

## Known gaps (carried from README)

- Kavita backend's field mapping for populated series/chapter data, and
  the OPDS backend's PSE/CBZ page streaming, are verified for routing/
  auth/parsing against live servers but not against real populated
  content end-to-end.
- No collections/read-lists screens yet.
- Smart panel view is a simple gutter-variance heuristic - opt-in only.
- App icons are still Flutter's placeholder icons.
- iOS build is configured but unverified (no Mac/Xcode available here).
