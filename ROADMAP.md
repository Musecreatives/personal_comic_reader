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
  `100.108.109.63:5577`): a server-rendered file-management tool
  (rename/organize comics on disk), no JSON API. Real integration would
  mean reverse-engineering its internal form/AJAX endpoints — nontrivial.
  **Decision: parked until after the UI/UX pass below.** Options on the
  table when we get back to it: give it a `clu.shaddai.home` Caddy entry
  and leave it standalone, embed it as a link/webview in the app, or a
  full native rebuild of its features in Shaddai Reader's own UI.
- **Komga vs. Kavita**: both stay configured, no consolidation planned
  right now.

## Active thread: Paperback import

Waiting on a fresh backup export from the Paperback iOS app (Settings >
Backups > Create/Export Backup) to inspect the real file format before
designing a migration path into Komga/Kavita/Suwayomi's libraries +
reading history. Not started beyond this — no schema assumptions made
yet.

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
