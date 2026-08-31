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

## Infrastructure incident: 2026-08-25 mergerfs drive drop

The migration's sustained write load (library adds + ~9,200 chapter
read-state writes to Suwayomi, 20 volume adds to Kapowarr) exposed a
real hardware fragility: the "external" USB drive backing part of the
`/mnt/media-pool` mergerfs union (which Suwayomi, Komga, Kavita,
Kapowarr, and CLU all store data on) physically disconnected mid-write,
then reconnected under a new device name (`/dev/sdb1` &rarr; `/dev/sdd1`)
without cleanly replacing the stale mount - leaving `/mnt/external`
double-mounted and every app on that pool erroring (Suwayomi H2
"database has been closed", Komga `SQLITE_CORRUPT`, Kavita's `kavita.db`
truncated to 0 bytes).

**Recovery** (done, verified): stopped all six containers on that pool
(suwayomi, komga, kavita, kapowarr, clu, komf) to release open file
handles - mergerfs itself doesn't release them until every process
with a file open on a branch has closed it, which was the actual
blocker on unmounting, not mergerfs itself. Unmounted cleanly, `fsck
-n`'d the drive (clean, no corruption - only in-flight writes were
lost), remounted, restarted everything. Suwayomi (245/248 titles + all
categories intact), Komga, and Kapowarr (all 24 volumes intact) came
back with no real data loss. Kavita's `kavita.db` was zeroed and had to
be restored from its own same-day 02:00 automated backup - essentially
no data lost since nothing had been written to Kavita that day.

**Not yet addressed**: the drive itself is the real risk here - it's a
physical USB connection that dropped under load once already. Worth
checking the cable/enclosure, or planning to replace/retire it from the
mergerfs pool, before any future write-heavy operation like this one.

## Infrastructure incident: 2026-08-29 mergerfs branch wedge + Kapowarr DB corruption

A *different* failure mode than the 08-25 drop: this time `hdd1tb`
(`/dev/sdb1`) went into ext4's `emergency_ro` (kernel-detected on-disk
inconsistency), but the mergerfs union itself stayed listed as mounted -
it just hung on every real I/O call for tens of minutes at a time. CLU
was found completely wedged (accepting TCP, never answering, `docker
kill -9` couldn't even land - classic D-state). The mergerfs-watchdog
timer installed after the 08-25 incident didn't catch this: it only
checks `mountpoint -q`, which doesn't distinguish "unmounted" from
"mounted but wedged" - it just blocks until the wedge clears, so the
watchdog's own runs silently stretched from instant to 21 -> 42 -> 51
minutes without ever alerting. Fixed (deployed 2026-08-29): every check
in `deploy/mergerfs-watchdog.sh` is now wrapped in `timeout`, so a
wedged branch is treated as its own distinct, immediately-alerting
failure instead of making the watchdog hang too.

**Real damage**: Kapowarr's live `Kapowarr.db` was corrupted
(`sqlite3.DatabaseError: database disk image is malformed`) - every
volume/issue/download-history row unreadable, even on a plain read.
Root cause: a write landed while `hdd1tb` was mid-wedge.

**Recovery** (done, verified, no data lost): found three other copies of
`Kapowarr.db` scattered across mergerfs branches and the leftover
`/mnt/media-pool-shadow-backup-20260828` directory (fallout from 08-25's
forking risk) - two were empty stubs, but the copy on the `external`
branch was fully intact (`PRAGMA integrity_check` = ok) with all 24
volumes, 180 issues, and 23 download-history rows matching the real
library. Restored it as the live database (corrupted original kept
alongside as `Kapowarr.db.corrupted-20260829`, nothing deleted).
Verified via API afterward: full volume list back with correct issue
counts and file sizes.

**Also done same session**: added qBittorrent to Kapowarr as a torrent
download client (`external_download_clients` table - Kapowarr's own
pluggable client system, confirmed via source read at
`/app/backend/base/definitions.py` / `/app/frontend/api.py`), connection
test passed. **Confirmed Kapowarr has no Usenet/NZB support at all** -
found the exact comment in `definitions.py`: "Future proofing... in the
future there'll be sources like 'torrent' and 'usenet'" - it's an
unbuilt feature, not a config gap. The user's NZBGeek subscription can't
be plugged into Kapowarr as it stands; its real acquisition sources
today are GetComics-scraped links only (Mega, MediaFire, WeTransfer,
Pixeldrain, GetComics direct/torrent).

**Correction, discovered 2026-08-30**: Suwayomi was *also* hit by this
incident, not just Kapowarr - missed at the time because I only checked
Kapowarr. Its own automated H2 backups (`backups/*.tachibk` under
`/mnt/media-pool/comics-manga/suwayomi/data/`) show the library was
healthy (796KB, 257 manga) at the 2026-08-29 00:00 auto-backup, then
collapsed to a near-empty 354-byte backup by 16:59 that same day -
squarely inside the incident window. Surfaced 2026-08-30 when the user
reported Suwayomi (their active source) showing 0 series despite
connecting fine. **Recovery** (done, verified, no data lost): used
Suwayomi's own `restoreBackup` GraphQL mutation (multipart file upload,
polled via `restoreStatus`) against the last healthy pre-incident backup
- much cleaner than a raw file swap since Suwayomi has real built-in
backup/restore tooling, unlike Kapowarr. Full library and all custom
categories (Reading 58, S Tier 40, A Tier 53, B Tier 47, C Tier 22,
Unread 49, Comics 10, Manga 7, plus custom lists) confirmed back via its
GraphQL API. **Lesson for next time**: when this pool wedges again,
check *every* app that stores a database on it, not just the one that
happens to throw an obvious error first - a service can look "connected
fine" while quietly serving an empty/reset database.

**Correction #2, same day**: the first `restoreBackup` above looked
successful (categories/manga counts came back correctly via the GraphQL
API) but was actually incomplete - it worked only because Suwayomi's
JVM had been running continuously since before the incident and had
parts of the corrupted `database.mv.db` cached in memory, papering over
the underlying file corruption. A user report ("Suwayomi is active but
not feeding manga/comics", `StubSource$SourceNotInstalledException` on
`/fetchChapterPages`) plus a routine restart to pick up an unrelated fix
exposed the real state: the H2 file itself was physically corrupted
(`EOFException` reading past its own end-of-file on cold boot) and the
container crash-looped on startup. Also separately broken: extensions
(Mangabat, Mangakakalot, MangaKatana, Kissmanga.in, Flame Comics,
Read Comics Online, Toonily.me, MangaBuddy/ManhwaBuddy, plus a few
others) showed `isInstalled: false` in a fresh database even though
their `.jar` files were still physically present in
`suwayomi/data/extensions/` - Suwayomi tracks "installed" purely via its
own DB records, not by scanning disk, so a fresh/restored DB with no
matching install record treats a present jar as not-installed.

**Full recovery** (done, verified with a real end-to-end page fetch):
1. Stopped the crash-looping container.
2. Moved the corrupted `database.mv.db`/`database.trace.db` aside to
   `suwayomi/data/corrupted-20260830/` (kept, not deleted) so Suwayomi
   would create a fresh database on next boot.
3. Started clean - confirmed a healthy boot with no errors.
4. Reinstalled all 14 previously-used extensions via the
   `updateExtension(patch: {install: true})` mutation. 4 succeeded
   immediately; the other 10 hit `FileAlreadyExistsException` (their old
   jars were still sitting in the extensions folder from before, and
   install doesn't overwrite) - deleted those specific stale jars
   (freely re-downloadable, not user data) and retried; all 14 then
   installed cleanly.
5. Re-ran `restoreBackup` against the same 2026-08-29 00:00 pre-incident
   backup, now against a database that has its extensions properly
   registered. Verified for real this time: fetched a real chapter via
   `fetchChapterPages` (Mangabat, 131 pages) and downloaded a real page
   image (200 OK, 122KB) through the REST endpoint - not just an API
   response that looked right.

Also noted, not a bug: the library shows two "Default" categories (one
with 1 manga, one empty) - confirmed present identically across both
restore attempts, so it's baked into the actual backup/pre-incident
data itself, not something introduced by any of this recovery work.

**Still not addressed**: same as 08-25 - the physical drive behind
`hdd1tb` needs a real hardware check (cable/enclosure/replacement),
independent of whatever fixed today's `emergency_ro` state. Two
distinct incidents on two different physical drives in the same pool in
five days is a pattern, not a fluke.

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
  **Decision (final, 2026-08-30): kept standalone, no in-app
  integration.** Endpoints were mapped live (confirmed working, zero
  auth on any of them: `/api/browse`, `/api/continue-reading`,
  `/api/favorites/*`, `/api/reading-lists/*`, `/api/mark-comic-read`,
  `/api/reading-position`, plus destructive file ops like
  `combine-cbz`/`delete-multiple`/`scan-directory`), but CLU's built-in
  reader doesn't beat what Shaddai Reader already has, and its real
  value - crop/combine/rescan/missing-file-check - is file-maintenance
  tooling Shaddai Reader was never meant to do. Wiring it in would've
  been real engineering effort (new backend client, 2-3 screens, action
  confirmations for an unauthenticated destructive API) for close to
  zero reading-experience payoff. User opens it directly at
  `100.108.109.63:5577` when needed; nothing to build here.
- **Komga vs. Kavita**: **decided 2026-08-30** — user is satisfied with
  Komga + Suwayomi covering the whole library and isn't actually reading
  through Kavita day to day. Kavita is being retired as a configured
  server (removed via Settings → Servers in-app, since server configs
  are per-device local storage - no code change needed). Not a CLU swap:
  CLU has no OPDS support and wasn't built to be a reading backend the
  way Komga/Kavita/Suwayomi are, so it can't take Kavita's role in the
  app even if the user prefers it for library maintenance.

## Shipped 2026-08-31: Suwayomi Maintenance panel

Direct follow-up to the 08-30 incident, which needed 20+ manual SSH/GraphQL
calls to diagnose and fix. New Settings → "Suwayomi maintenance" screen
(`lib/features/suwayomi/suwayomi_maintenance_screen.dart`, client at
`lib/backends/suwayomi/suwayomi_maintenance_client.dart`, route
`/settings/suwayomi`) surfaces exactly what that incident needed by hand:
- Health summary (total manga, category count, extensions installed X/Y).
- Per-extension install state + one-tap reinstall for the 14 extensions
  this library actually uses (`knownExtensionPackages`) - surfaces a
  `FileAlreadyExistsException` from a stale server-side jar as a clear
  message rather than a raw stack trace (deleting server files isn't
  something this does automatically, same read-only-by-design posture as
  Kapowarr).
- "Create backup now" (Suwayomi's `createBackup` mutation).
- "Restore from file" (`.tachibk` upload via `file_picker`, single confirm
  dialog, polls `restoreStatus` until `SUCCESS`/`FAILURE`) - the same
  multipart flow run by hand during the incident, now in-app.

**Known gap, not built**: Suwayomi has no GraphQL query for *existing*
backup files already sitting in its own `backups/` folder (confirmed -
only `createBackup`/`restoreBackup` mutations exist) - so the panel can
create a new backup or restore an uploaded one, but can't show/pick from
backups already on the server. Would need either a Suwayomi-side change or
a REST-level workaround to close.

**Scoped, not built this pass** (full writeup in the approved plan):
extension *discovery/browsing* (Suwayomi's own web UI already covers
this well), per-title source management, chapter bulk actions, a download
queue view, advanced search filters - all reference ideas from Paperback
screenshots that substantially duplicate what Suwayomi's own `/suwayomi`
web UI already provides one tap away. Scan/manga update metadata display
and Komga/Kavita/Suwayomi metadata-refresh actions are flagged as
worthwhile small follow-ups, not bundled into this pass.

## Active thread: cross-device sync & multi-user accounts

Kicked off 2026-08-30 by two related asks: real persistence "that stays
live" across desktop/iOS PWA/Android/tablet, and sharing the app with a
friend (confirmed: needs real separate accounts, not shared credentials).

**Phase 1 shipped 2026-08-30**: a new self-hosted `shaddai-sync` service
(`deploy/sync-service/` - FastAPI + SQLite, opaque bearer-token sessions,
one generic `sync_records` table so future features need zero schema
changes) plus a login/create-account gate in the app and one fully synced
store (History - reads across devices once you're signed in). Deployed:
container running on the server (`docker run ... shaddai-sync`, port
8600), Caddy `/sync/*` route added and Caddy force-recreated, app rebuilt
and redeployed. Its SQLite file deliberately lives on the root disk
(`/home/server/docker/sync-service/data`), **not** `/mnt/media-pool`,
given that mount's two-corruption-incidents-in-five-days track record
this same week. A nightly backup script (`sync-db-backup.sh`) is deployed
and tested working; the `.service`/`.timer` pair to actually schedule it
still needs a one-time `sudo systemctl enable --now sync-db-backup.timer`
on the server (no sudo access in this environment - same gap as the
mergerfs-watchdog timer's `TimeoutStartSec` addition).

Server credentials (Komga/Kavita/Suwayomi logins) deliberately stay
local-per-device, not synced - decided explicitly to keep the new service
from becoming a second place storing third-party passwords.

**Not yet built** (explicitly out of scope for this pass, same mechanical
pattern as History once needed): Collections, Appearance, and Reader
Settings sync. **Stats sync needs different logic**, not just repetition -
it has to sum pages/seconds per day across devices rather than
last-write-wins, since two devices reading the same day would otherwise
have one clobber the other. Also not built: any account management UI
beyond login/create (no password reset, no removing a user), and
real-time/websocket push (sync happens on login + app resume only, not
continuously).

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
- **Applied 2026-08-25**: all 248 matched titles added to Suwayomi's
  library (246 initially + 2 MangaBuddy-sourced titles added after
  confirming MangaBuddy = ManhwaBuddy is correct), the 11 Paperback tabs
  recreated as categories, and read chapters marked read (~99% match
  rate; remaining gap is chapter-numbering mismatches between
  Paperback's chapter list and the current Suwayomi source listing -
  low-impact, not investigated further).
- **Still open**: the 8 manga/manhwa/doujin titles with no Kapowarr/CLU
  acquisition path (MangaForest, UToon, TooniTube, BatoTo,
  ReadAllComics, Atsumaru, NHentai sources) - alternative sources not
  yet researched.
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
