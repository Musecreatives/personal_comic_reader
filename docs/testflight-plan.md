# TestFlight + remote access plan

Goal: friends install Shaddai Reader from TestFlight and read from the home
server over the internet, without Tailscale, without being able to damage the
server or fill its disks.

Status: **plan only** - nothing below is built yet unless marked ✅.

---

## 1. What already supports multiple users

| Piece | Multi-user today? | Notes |
|---|---|---|
| Sync service accounts | ✅ | `/auth/register`, `/auth/login`, bearer token. The app requires a sign-in before anything else (`main.dart` routes to `/login` without a token). |
| Synced per-user data | ✅ | `appearance`, `collections`, `reader_settings`, `stats` (`lib/core/sync/resource_sync.dart`). Problem reports are tied to the account. |
| Server list + credentials | ✅ per device | Each install keeps its own servers; passwords are in secure storage. |
| Komga | ✅ | Real per-user accounts, per-user read progress, library sharing restrictions, age-rating limits. **This is the server friends should read from.** |
| Local library / device downloads / history | ✅ per device | Never touches the server. |
| Suwayomi | ❌ | One shared library and one shared read progress. The app sends **no credentials** (`suwayomi_backend.dart`: "trusted network"). A friend marking a chapter read marks it for you too. |
| Kapowarr | ❌ | One admin. The app can add volumes (`POST /api/volumes`), which start downloads onto your disks. |
| Media pool (WebDAV) | ⚠️ | Per device, but whoever has the credentials can write into your Nextcloud library folders. |

## 2. What to limit (storage, bandwidth, abuse)

**Server disk**
- Friends never get Kapowarr or Suwayomi access → nobody but you can trigger
  server-side downloads. (Suwayomi `enqueue` and Kapowarr add-volume both
  write to disk.)
- Friends never get media-pool (WebDAV) credentials → no uploads.
- Sync service: cap per user - e.g. 5,000 records per resource, 20 problem
  reports/day, 256 KB per report (reports attach the last 80 network calls
  and logs, `problem_reports.dart`).

**Bandwidth (your home upload is the real limit)**
- Caddy `rate_limit` per client IP on the public port.
- App: cap concurrent device downloads at 2 for non-owner accounts.
- Komga: page images are already served at original size; if upload is
  tight, consider Komga's page resize/transcode later.

**Accounts**
- Close open sign-up: invite codes (or you create accounts by hand).
- One Komga account per friend, each limited to the libraries you choose.

## 3. Features that could compromise security → owner-only

These stay in the app for you but are hidden (and unreachable) for friends:

| Feature | Why | Where |
|---|---|---|
| Suwayomi maintenance: restore backup, server settings, install/remove extensions | Full control of the Suwayomi server | `features/suwayomi/suwayomi_maintenance_screen.dart`, `backends/suwayomi/suwayomi_maintenance_client.dart` |
| Suwayomi remove-from-library, migrate extension, fetch chapters, server download queue | Changes the shared library | `series_screen.dart`, `collections/migrate_sheet.dart` |
| Kapowarr search/add, settings | Starts downloads on your disks | `features/kapowarr/`, `features/search/acquire_search.dart` |
| Media pool upload | Writes into your Nextcloud | `features/settings/media_pool_settings_screen.dart` |

**Hiding in the UI is not the security boundary.** The boundary is that
Suwayomi, Kapowarr and Nextcloud are **not published on the internet at
all** (section 4). UI gating just keeps the app tidy for friends.

Gating mechanism: the sync service's `/auth/me` returns a `role`
(`owner` | `member`); the app hides owner features for `member`.

Other hardening:
- **Hard-coded Tailscale address**: `SyncClient.defaultBaseUrl()` falls back to
  `http://100.108.109.63:8600`. Needs to become the public HTTPS URL.
- **iOS `NSAllowsArbitraryLoads = true`** (`ios/Runner/Info.plist`): replace
  with `NSAllowsLocalNetworking` once everything public is HTTPS. Beta App
  Review asks for a justification if it stays.
- **Diagnostics** already skips `/auth/` bodies and logs before API keys are
  added - OK. Keep it; reports only reach your own sync DB.
- Add `ITSAppUsesNonExemptEncryption = false` to Info.plist (standard HTTPS
  only) so every TestFlight build doesn't stop for the export-compliance
  question.

## 4. Getting the servers online without Tailscale (AirVPN port forward)

**What goes public:** Komga (reading) + sync service. **Nothing else.**
Suwayomi, Kapowarr, Nextcloud admin, SSH stay Tailscale-only for you.

```
friend's iPhone ──HTTPS──▶ reader.<your-domain>:<airvpn-port>
                             │  (CNAME → <name>.airdns.org → AirVPN exit IP)
                             ▼
                      AirVPN server ──WireGuard──▶ gluetun container
                                                     │ (Caddy shares its network)
                                                     ▼
                                             Caddy :<airvpn-port>
                                              ├─ /komga/* → komga:25600
                                              ├─ /sync/*  → sync-service:8600
                                              └─ everything else → 404
```

Steps:
1. **AirVPN**: in Client Area → Ports, reserve one port (AirVPN assigns
   high ports, not 443). Enable its DDNS name (`<name>.airdns.org`).
2. **gluetun** container with AirVPN WireGuard config and
   `FIREWALL_VPN_INPUT_PORTS=<that port>`.
3. **A second Caddy** (public edge) with `network_mode: "service:gluetun"`,
   listening on that port, proxying only `/komga` and `/sync` over the
   docker network. Keep your existing internal Caddy as it is.
4. **TLS**: Let's Encrypt can't use the HTTP/TLS challenges on a
   non-443 port, so use the **DNS challenge**: a domain you own (≈ $10/yr)
   on Cloudflare DNS, Caddy built with the `caddy-dns/cloudflare` module,
   a scoped API token (Zone:DNS:Edit on that one zone only).
   `reader.<your-domain>` CNAME → `<name>.airdns.org`.
5. In the app, friends' server URL becomes
   `https://reader.<your-domain>:<port>/komga`, sync
   `https://reader.<your-domain>:<port>/sync`.

Caveats: AirVPN exit IPs are shared and change when gluetun reconnects to
another server (the DDNS CNAME follows it). Pin a server/country in gluetun
for stability. Home **upload** speed caps everyone's page loads.

## 5. App changes needed (build order)

1. Configurable sync URL (settings + sign-in screen), default = public HTTPS.
2. Server presets: after sign-in, offer "Add Shaddai Komga" pre-filled
   with the public URL.
3. `role` from `/auth/me`; hide section 3's owner features for members.
4. Member download concurrency cap.
5. Info.plist: ATS tightening, `ITSAppUsesNonExemptEncryption`.
6. Real app icon (README "Known gaps" says placeholder; App Store requires
   a proper 1024 px icon).
7. Sync service (server repo `~/docker/sync-service`): invite codes, role
   column, quotas, rate limits.

## 6. TestFlight

1. **Apple Developer Program** (US$99/yr) - required; the free Apple ID can't
   use TestFlight. Register the App ID `home.shaddai.reader`.
2. App Store Connect → create the app → TestFlight tab.
3. Build/sign with **Codemagic** (`codemagic.yaml` workflow `ios-testflight`
   already exists; fill in the App Store Connect API key in Codemagic, then
   push a `v*` tag).
4. **Internal testing** first (you; no review, up to 100 team members).
5. **External group** for friends via a public link or emails (up to
   10,000). The first build per version goes through **Beta App Review**:
   - Provide a **demo account**: a Komga user that only sees
     public-domain comics, plus a sync account.
   - Reviewers must not see Suwayomi sources/extensions - another reason
     members never get Suwayomi.
6. Builds expire after 90 days; each new tag uploads a fresh one.

## 7. Feature roll-out backlog

Not TestFlight blockers - queued for after the steps above.

- [ ] **Change a series' cover.** ComicVine lookup fills in text details
  only; there's no way to pick a better cover.
  - Cover options: any page of the book, the ComicVine volume/issue cover
    (`image.original_url` from the lookup already fetched), or an image
    file from the device.
  - Imported (local) series: store the chosen image with the series (a
    `coverPath`/bytes field on `LocalSeriesRecord`), and have
    `LocalBackend` return it instead of page 0.
  - Komga series: upload it as the series poster (Komga's series
    thumbnails API), so every client sees it.
  - Suwayomi: no custom-cover API - leave as is.
- [ ] **Chunked media-pool uploads.** One PUT per book means a 2 GB
  omnibus hits server body limits (Nextcloud's image defaults to 1 GB;
  the server now allows 16 GB) and a dropped connection restarts from
  zero. Use Nextcloud's chunked upload (`/remote.php/dav/uploads/`, ~50 MB
  chunks) when the server supports it; plain PUT for other WebDAV servers.
- [ ] **Scan / refresh a library from the app.** Today a new file only
  shows up after Komga's own scan (or a manual scan in Komga's web UI).
  - Komga: "Scan library files" (`POST /api/v1/libraries/{id}/scan`) and
    "Refresh metadata" (`POST /api/v1/libraries/{id}/metadata/refresh`)
    in the library's menu; admin-only on Komga, so owner-only here.
  - Run a scan automatically after a successful media-pool upload.
  - Suwayomi: "Update library" (its library update GraphQL mutation).
  - Pull-to-refresh on library screens re-fetches from the server.
- [ ] **Sign out.** `SyncClient.logout()` exists but nothing in the UI
  calls it. Add Sign out to Settings: call `/auth/logout`, clear the token
  and the synced stores' local copies (servers, connections, collections,
  history), detach sync, and return to `/login`. Ask first whether to keep
  downloads and imported comics on the device.
- [ ] **Include ComicInfo.xml in media-pool uploads** so edited details
  (summary, credits, genres) reach Komga.
- [ ] **Encrypt synced secrets on the device** before upload
  (`lib/core/sync/connections_sync.dart`, marked `ponytail:`). Required
  before friends' credentials live in the sync DB.
- [ ] **Suwayomi login support** (basic auth) - the backend sends no
  credentials today.

## 8. Open questions for the owner

- Which domain will you use (or should we buy one)?
- Do friends need manga (Suwayomi) at launch, or is Komga enough? If they
  need manga: Kapowarr/Suwayomi downloads → a Komga library folder, so they
  read it through Komga.
- How many friends, and what's the home upload speed? (Sets rate limits.)
- Invite codes, or you create accounts yourself?
