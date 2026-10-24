# Server operations

The home server that Shaddai Reader talks to: how to reach it, where things
live, what runs on its own, and what to do when the storage pool drops out.
No passwords or keys belong in this file.

## Access

- SSH: `ssh server@100.108.109.63` (Tailscale only). Key-based; the `server`
  user has passwordless `sudo`.
- Claude Code on the owner's PC is allowed to run `ssh`/`scp` to this host
  without prompting (`.claude/settings.local.json`, not committed).

## What runs where

| Service | Container | Reached at | Data |
|---|---|---|---|
| Sync service (accounts, history, settings) | `shaddai-sync` | `100.108.109.63:8600`, public `https://reader.shaddaicommunications.com/sync` | `~/docker/sync-service/data/sync.db` (internal SSD) |
| Komga (comics and manga for everyone) | `komga` | `100.108.109.63:8081`, public `/komga` | `/mnt/media-pool/comics-manga/komga/config` |
| Suwayomi (manga sources, owner only) | `suwayomi` | `http://100.108.109.63:4567` (Tailscale only) | `/mnt/media-pool/comics-manga/suwayomi/data` |
| Kapowarr (comic downloads, owner only) | `kapowarr` | `100.108.109.63:5656` | `/mnt/media-pool/comics-manga/kapowarr/db` |
| Caddy (public edge) | `caddy` | public HTTPS | `~/docker/caddy/Caddyfile` |

- Komga, Suwayomi and Kapowarr: `~/docker/comics-manga/docker-compose.yml`.
  Ports are bound to the Tailscale address only.
- The sync service is started by hand, not by compose. Its source is
  `~/docker/comics-manga/sync-service/` (not in this repo). To redeploy:
  back up `sync.db`, `docker build -t shaddai-sync .`, then recreate with the
  same name, `--restart unless-stopped`, `-p 100.108.109.63:8600:8600`,
  `-v /home/server/docker/sync-service/data:/data`, and the existing
  `SYNC_INVITE_CODE` and `SYNC_DB_PATH=/data/sync.db` environment. The
  previous image is kept as `shaddai-sync:pre-roles`.
- `/auth/me` returns `role`: the first account ever created is `owner`,
  every other account is `member` (2026-10-23).

## Manga for friends

Suwayomi downloads chapters as CBZ (`server.downloadAsCbz = true`) with
auto-download of new chapters, into `server.downloadsPath = "/manga"`. That
folder is `library/manga` on the pool, which Komga reads as its **Manga**
library (scan on start and every 6 h). Friends read manga through Komga with
their own accounts; they never reach Suwayomi.

`server.conf` overrides the compose file's `DOWNLOADS_PATH`. If downloads
stop showing up in Komga, check that `downloadsPath` is still `/manga`.

## The storage pool

`/mnt/media-pool` is a mergerfs union of four USB drives, all behind one hub:

| Branch | Drive |
|---|---|
| `/mnt/hdd1tb` | 1 TB (label `backup2`, fstab UUID `33ca0b64-…`) |
| `/mnt/hdd1tb2` | WD 1 TB |
| `/mnt/external` | Toshiba 500 GB (label `Backup`) |
| `/mnt/flash16gb` | 16 GB flash |

A file lives on exactly one branch, so a database can sit on one drive and
its write-ahead log on another. That is why one drive dropping out can break
an app, and why an app running through an outage can leave a second copy.

`hdd1tb` has failed three times: 2026-08-29, 2026-09-22 and 2026-10-24. The
last one was the whole USB hub resetting. Check the hub's power supply and
cables.

### Watchdog

`~/docker/comics-manga/mergerfs-watchdog.sh`, run as root every 5 minutes
by `mergerfs-watchdog.timer`. Alerts go to ntfy topic `homelab-alerts`.

- Remounts the union if it is unmounted; alerts if it is wedged.
- Alerts when a branch mount is shut down, read-only, or stacked twice.
- Alerts when Suwayomi's newest backup looks empty.
- **Since 2026-10-24:** when any branch's live mount is unhealthy or missing,
  it stops `komga`, `suwayomi` and `kapowarr`, records them in
  `/var/lib/mergerfs-watchdog/stopped-apps`, and alerts. Once every branch is
  healthy and each app's database is in exactly one place, at least 1 MB and
  readable, it starts them again and sends an all-clear. If a database is in
  two places it keeps them stopped and alerts instead.
- It never remounts a branch or moves files: that stays a manual step.
- Test it without touching anything:
  `sudo env CHECK_ONLY=1 bash mergerfs-watchdog.sh`, or
  `sudo env DRY_RUN=1 MOUNTS_FILE=<fake mounts> bash mergerfs-watchdog.sh`.

## When a pool drive drops out

1. **Stop the apps first** (the watchdog now does this):
   `docker stop komga suwayomi kapowarr`.
2. **Find the drive:** `lsblk`, `sudo dmesg -T | grep -iE "usb .*disconnect|I/O error"`.
3. **Reconnect it** (cable, hub power). It usually comes back under a new
   device name and is remounted by fstab on top of the dead mount. Leave the
   dead mount underneath; a reboot clears it. Do not `umount` the top entry.
4. **Look for duplicate databases** before starting anything:
   ```bash
   for b in hdd1tb external flash16gb hdd1tb2; do
     ls -la /mnt/$b/comics-manga/{komga/config,suwayomi/data,kapowarr/db} 2>/dev/null
   done
   ```
   A small (4 KB) `database.sqlite` beside a large one on another branch is
   an empty one created during the outage. Move it aside (never delete):
   `sudo mkdir <dir>/empty-db-<date> && sudo mv <dir>/database.sqlite* <dir>/tasks.sqlite* <dir>/empty-db-<date>/`.
5. **Start the apps** (or let the watchdog do it): `docker start komga`,
   `docker restart suwayomi kapowarr`.
6. **Check:** Komga answers 401 at `/api/v1/libraries`; Suwayomi's GraphQL
   returns its manga count; Komga's `USER`, `LIBRARY` and `SERIES` tables
   have rows.

### 2026-10-24 incident

At 12:08 the USB hub reset and every pool drive dropped. Suwayomi's and
Komga's databases became unreadable. When the drives came back at 12:48,
`hdd1tb` re-attached before `external`; Komga, still running, found no
database and created an empty one on `hdd1tb`, which hid the real one (on
`external`). Recovery followed the steps above. The empty files are kept in
`komga/config/empty-db-20261024/` on `hdd1tb`. Komga's reading progress saved
after its last checkpoint (23 Oct 14:17) was lost with the replaced
write-ahead log; the app's own synced history was not affected. Suwayomi's
database was intact (761 manga).

## Recommended next steps

- Move Komga's, Suwayomi's and Kapowarr's config and databases off the pool
  onto the internal SSD, as the sync service already is. The library files
  can stay on the pool.
- Reboot when convenient to clear the stacked dead mounts.
- Replace or re-power the USB hub.
