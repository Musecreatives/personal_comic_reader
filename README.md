# Shaddai Reader

A Flutter comic/manga reader modeled on the iOS app Panels, targeting
Flutter web (PWA) first and iOS later from the same codebase. Talks to
self-hosted Komga, Kavita, Suwayomi, and generic OPDS 1.2 servers, plus
a read-only Kapowarr status view.

## Status

**All 5 phases complete**: full reader (single/double/vertical modes,
zoom, offline-first downloads, a Wi-Fi-only download queue, an
experimental smart panel view), four working reader backends (Komga,
Kavita, Suwayomi, OPDS 1.2+PSE), local reading stats, an iPad/wide
two-column library layout, Caddy-based same-origin PWA hosting, and iOS
build configuration (bundle ID, Info.plist, Codemagic). See
`CHANGELOG.md` for what shipped in each phase, including two real bugs
found and fixed during manual verification (a swallowed-error infinite
spinner in Phase 3, a URL-as-path-segment routing crash in Phase 5).

## Running

```bash
flutter pub get
flutter run -d chrome
```

On first launch you'll land on an empty state prompting you to add a
server (Komga, Kavita, Suwayomi, or OPDS) pointed at your instance, e.g.
`http://100.108.109.63:8081`.

## Building for web

```bash
flutter build web --release
```

Output lands in `build/web/`. `deploy/build.ps1` builds and deploys this
in one step - see Deploying below.

## Building for iOS

Requires a Mac with Xcode - not available in this repo's primary dev
environment (Windows), so this path is configured but not locally
verified:

```bash
flutter build ios --release --no-codesign   # unsigned sanity check
```

`codemagic.yaml` has two workflows: `ios-unsigned-check` (no signing
needed, just proves the project builds) and `ios-testflight` (needs an
App Store Connect API key configured in Codemagic's own settings, not
in this repo). Bundle ID is `home.shaddai.reader`.

## Testing

```bash
flutter analyze
flutter test
```

## Architecture

- `lib/core/backend/` — the `ReaderBackend` interface and shared models.
  UI code only ever depends on this interface, never on a concrete
  backend or an HTTP client directly.
- `lib/backends/komga/`, `lib/backends/kavita/`, `lib/backends/suwayomi/`,
  `lib/backends/opds/` — one implementation per server type. Entity IDs
  are opaque strings as far as the UI is concerned - Komga/Kavita/
  Suwayomi use plain IDs, OPDS uses full feed URLs, which is why every
  navigation call site `Uri.encodeComponent`s the ID before putting it
  in a route path (see CHANGELOG Phase 5 for the bug this fixed).
- `lib/core/downloads/` — the download queue (`DownloadManager`,
  `DownloadStore`) and offline-first page resolution
  (`PageCache` prefers a downloaded page over the network).
- `lib/core/panels/` — the experimental smart-panel-view gutter
  detector, a pure geometry function over an RGBA buffer.
- `lib/core/stats/` — local-only reading stats (pages/time per day,
  streak), never sent to any server.
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

## Known gaps

- Kavita backend's field mapping for populated series/chapter data, and
  the OPDS backend's PSE/CBZ page streaming, are both verified for
  routing/auth/parsing against live servers but not against real
  populated content end-to-end (Kavita: zero indexed series at the time
  of testing; OPDS: verified through Komga's real navigation/library
  feeds, but no populated OPDS-PSE book was available to exercise page
  streaming against). Worth re-checking once real content exists. See
  CHANGELOG Phases 3 and 5.
- No collections/read-lists screens yet (data-layer support exists on
  every backend that has the concept).
- Smart panel view is a simple gutter-variance heuristic - it will get
  non-grid layouts, bleeds, and borderless panels wrong. Opt-in via a
  button in the reader overlay (single-page mode only), never on by
  default.
- App icons are the default Flutter placeholder icons; needs real
  branding art before shipping.
- iOS build configuration is unverified beyond static inspection - no
  Mac/Xcode toolchain in this environment. Needs a real Codemagic run
  (or a Mac) before trusting it.
- `flutter analyze` should be run after any change and kept clean.
