# Shaddai Reader

A Flutter comic/manga reader modeled on the iOS app Panels, targeting
Flutter web (PWA) first and iOS later from the same codebase. Talks to
self-hosted Komga, Kavita, and Suwayomi servers, plus a read-only
Kapowarr status view.

## Status

**Phase 4 of 5 complete**: full reader, working Komga/Kavita/Suwayomi
backends, offline downloads with a Wi-Fi-only queue, offline-first page
resolution, a storage manager, an offline banner, and Caddy-based
same-origin PWA hosting. See `CHANGELOG.md` for what's done per phase.

## Running

```bash
flutter pub get
flutter run -d chrome
```

On first launch you'll land on an empty state prompting you to add a
server (Komga, Kavita, or Suwayomi) pointed at your instance, e.g.
`http://100.108.109.63:8081`.

## Building for web

```bash
flutter build web --release
```

Output lands in `build/web/`. `deploy/build.ps1` builds and deploys this
in one step - see Deploying below.

## Testing

```bash
flutter analyze
flutter test
```

## Architecture

- `lib/core/backend/` — the `ReaderBackend` interface and shared models.
  UI code only ever depends on this interface, never on a concrete
  backend or an HTTP client directly.
- `lib/backends/komga/`, `lib/backends/kavita/`, `lib/backends/suwayomi/`
  — one implementation per server type.
- `lib/core/downloads/` — the download queue (`DownloadManager`,
  `DownloadStore`) and offline-first page resolution
  (`PageCache` prefers a downloaded page over the network).
- `lib/core/kapowarr/` — a separate, read-only client for Kapowarr's
  status (not a `ReaderBackend` - Kapowarr acquires comics, it doesn't
  serve readable pages).
- `lib/core/storage/` — server configs, credentials, and the
  last-visited-route store (Hive + flutter_secure_storage, both
  web-safe).
- `lib/app/` — Riverpod providers, go_router routes/router factory,
  theme, the offline banner.
- `lib/features/` — one folder per screen/feature area.

## Deploying (same-origin PWA hosting via Caddy)

Serving the app from its own hostname, same-origin with Komga/Kavita
behind a reverse proxy, avoids the CORS block a browser hits when
talking directly to a bare server IP (Komga/Kavita don't send
`Access-Control-Allow-Origin`).

1. **Build and copy the release bundle to the server:**
   ```powershell
   powershell -File deploy/build.ps1
   ```
   This runs `flutter build web --release --base-href /` and `scp`s
   `build/web/` to `server@100.108.109.63:/home/server/docker/caddy/sites/reader/`
   over Tailscale. Requires a passwordless SSH key already authorized
   for that host - the script does not prompt for a password.

2. **One-time server setup**, if not already done:
   - Bind-mount that sites directory into the Caddy container as
     `/srv/reader` (see the comment block in `deploy/Caddyfile.snippet`
     for the compose `volumes:` line).
   - Append `deploy/Caddyfile.snippet` to
     `/home/server/docker/caddy/Caddyfile`, then reload Caddy:
     ```bash
     docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
     ```
   - In AdGuard Home, add a DNS rewrite: `reader.shaddai.home` →
     `100.108.109.63`.

3. **On iPhone**: open `https://reader.shaddai.home` in Safari, then
   Share → Add to Home Screen. The app defaults new Komga/Kavita server
   URLs to `/komga` and `/kavita` (same-origin) automatically when it
   detects it's being served from that hostname - direct-IP entry still
   works fine for local dev, both from `flutter run -d chrome` and when
   opening the deployed site directly by IP.

## Known gaps after Phase 4

- Kavita backend's field mapping for populated series/chapter data is
  best-effort (verified for auth/routing/pagination against a live
  instance with zero indexed series) - worth re-checking once real
  content is scanned in. See CHANGELOG Phase 3.
- No collections/read-lists screens yet (data-layer support exists on
  every backend). Planned for a later pass.
- App icons are the default Flutter placeholder icons; needs real
  branding art before shipping.
- Smart panel view, reading stats, and the OPDS backend are Phase 5.
- `flutter analyze` should be run after any change and kept clean.
