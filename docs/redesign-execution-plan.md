# Redesign execution plan

Goal: keep Shaddai Reader exactly as capable as it is for the owner (every
admin and dev feature stays), make it feel native on iPhone, Android phone,
Android tablet, Windows and the web app, and make it easy and pleasant for
friends to read with you. Slow burn: one phase at a time, each one shipped,
tested on real devices and lived with before the next starts.

Design reference: the "Shaddai Reader Redesign" canvas (claude.ai artifact).
Its top rows are screenshots of the app as it is today; every redesigned
board keeps that layout and only changes chrome, controls, spacing, contrast
and motion. When the canvas and this plan disagree, the canvas wins for
looks and this plan wins for order.

Rules for every phase:

- **No feature removed or renamed.** Owner-only features are hidden for
  friends, never deleted. Routes, sync data and stored settings keep their
  shape.
- **Same layout as today, made native.** Home hero, shelves, Series header
  with stats row, "CH n" chapter rows, Library chips and grid, Settings rows
  with icons, the reader's page footer: all stay.
- **The logo and series metadata always show.** The real app icon
  (`assets/icon/app_icon.png`) is bundled, never fetched, and appears in the
  Settings header, desktop title bar / sidebar and launch screen. Series
  metadata (credits, tags, summary, read/unread counts, source) is shown
  wherever the series is, and covers fall back to the title placeholder when
  no image loads.
- **Downloads first.** Reading from this device is the default experience
  for friends; streaming from the home server is the fallback.
- **Each phase ends green:** `flutter analyze` clean, `flutter test` passing,
  tested on the Android tablet plus at least one phone, and a short entry in
  `CHANGELOG.md`.

## Test devices

| Device | How | Covers |
|---|---|---|
| Android tablet (yours) | USB debugging, `flutter run -d <id>`; release APK via `flutter build apk --release` | Tablet layouts (rail, two panes, spreads), Material chrome, predictive back, downloads |
| Android phone | Same APK | Material phone layout |
| iPhone | TestFlight internal build (Codemagic `ios-testflight`) | iOS chrome, haptics |
| Windows PC | `flutter run -d windows` | Fluent pane, title bar, keyboard |
| Browser | `flutter build web` behind your Caddy | PWA install, offline |

Tablet widths to check: 600-839 dp (portrait, medium) and 840+ dp
(landscape, expanded).

## Phase 0: Baseline and quick fixes

1. **Fix the web start-up crash.** `ReadingStatsStore.init` calls
   `Random().nextInt(1 << 32)`; on the web `1 << 32` is `0`, so `nextInt`
   throws and a fresh browser (any new PWA user) never gets past start-up.
   Use `Random().nextInt(1 << 31)` or build the id from two smaller ints,
   and add a test.
2. **Review the open branch** `claude/loving-ritchie-f0lwy5`. It already has
   a first pass at platform chrome (adaptive nav, `showAppSheet`,
   `AppBackButton`, `Switch.adaptive`, Windows title bar, Android predictive
   back, PWA manifest). Compare each piece with the canvas, keep what
   matches, adjust what doesn't (for example the iOS glass bar and the
   tablet rail must keep today's look). Open it as a PR; merge only after
   the tablet and one phone have been used for a few days.
3. **Device setup:** Android tablet in developer mode, a debug and a release
   APK build that installs side by side (different application id suffix
   for debug).

Done when: web build starts on a clean browser profile; branch reviewed and
either merged or reworked; APK on the tablet.

## Phase 1: Friend-ready accounts (app + sync server)

From `docs/testflight-plan.md` section 5, in this order:

1. Configurable sync URL (sign-in and Settings), default the public HTTPS
   URL; drop the hard-coded Tailscale fallback for release builds.
2. Server presets after sign-in ("Add Shaddai Komga" pre-filled).
3. `role` from `/auth/me` (`owner` | `member`); hide owner-only features for
   members (Kapowarr, Suwayomi maintenance and library changes, media pool,
   People, Requests).
4. Per-friend permissions, invites and requests: server work in
   `~/docker/sync-service`, then app screens (Settings > People, Settings >
   Requests, friend "Ask for a series"). See
   `docs/prompts/permissions-invites-requests.md`, which is written to be
   handed to a local session.
5. Member download concurrency cap (2 at a time by default, per-friend
   override from People).
6. iOS `Info.plist`: ATS tightening, `ITSAppUsesNonExemptEncryption`.

Done when: a friend account signs in on a clean device, sees only Komga,
can read and download, can ask for a series, and you can approve it from
Requests.

## Phase 2: Downloads first, and honest status

Friends should mostly read offline: it saves your home upload and works on
bad networks.

1. Download controls with progress everywhere a chapter appears: ring per
   chapter, "Download unread" on the series, ON DEVICE count in the stats
   row, queue and storage screens (these exist; restyle them).
2. Smart downloads (opt-in, per device): keep the next N unread chapters of
   anything in progress on the device, Wi-Fi only by default, remove
   chapters a while after they are read, storage limit with a clear meter.
3. Offline and outage states (canvas row "When something is wrong"):
   device offline banner with what still works; server-not-responding card
   that says the internet is fine and shows each server's status; "Test
   connection" that checks address, server type and sign-in separately and
   points at the field to fix. Every error shown has **Copy error** and
   **Report this**.
4. Report a problem (canvas "Feedback with copyable errors"): recent errors
   with Copy and Add to report, Paste, attach logs, device info shown, and
   **Copy report** that produces Markdown ready to paste into Claude or a
   GitHub issue. Reuses `problem_reports.dart` and Diagnostics; no
   passwords or API keys ever included.

Done when: the tablet in airplane mode opens straight into downloaded
chapters with the offline banner; a stopped Komga shows the outage card;
a copied report pastes cleanly into an issue.

## Phase 3: Native chrome per platform

Keep the brand and the layouts; change the frame.

- **iOS:** floating glass tab bar (today's), large titles that collapse into
  a frosted bar, swipe back, press-in feedback, native action sheets for
  "More", iOS switches, haptics on tab change, download done and errors.
- **Android phone:** Material 3 navigation bar with pill indicator, ripples,
  predictive back, Material bottom sheets with grabber, snackbars with Undo,
  edge-to-edge.
- **Android tablet:** today's rail and mascot with the Material pill
  indicator; Home hero split (text left, cover right) so the empty band
  goes away; shelves as grids; Series two panes (details left, chapters
  right) as today; Reader two-page spreads in landscape with reading
  direction.
- **Windows:** Fluent navigation pane (Settings at the foot), tinted title
  bar, hover states, Ctrl+1-5 and Ctrl+F, sheets as centred dialogs.
- **Web PWA:** install banner, rail or sidebar by width, Ctrl+K search,
  any orientation, iOS home-screen meta.
- A per-device "Interface" override in Appearance for testing any style on
  any device.

Done when: each platform passes a walk-through of Home, Library, Series,
Reader, Search and Settings on its real device.

## Phase 4: Screen-by-screen polish

One screen per step, in this order, each matching its canvas board:
Home, Series, Reader, Library, Search (including the Kapowarr add sheet:
root folder, monitor new issues, search now), History, Settings (admin and
friend), Collections, Downloads, Storage.

Micro-interactions from the canvas "Micro-interactions" board, using the
existing `lib/app/motion.dart` tokens; page turns and keyboard shortcuts
never animate; everything respects Reduce Motion.

Small fixes found while capturing today's screens:
- Settings is a root tab but shows a back button; drop it on root tabs.
- Hero and series header show a stray book icon when a cover has no image;
  the placeholder should sit inside the cover only.
- Small grey metadata is slightly too faint; raise it to the canvas values.

## Phase 5: Support the server

- A "Support the server" page explaining that a 2 TB drive costs about
  ₦50,000 and what it gives everyone (more room for series). Shown to
  friends in Settings.
- **Payment:** Buy Me a Coffee and similar services may not pay out to
  Nigeria (check before choosing). Look at Nigerian options that give a
  shareable payment link (for example Paystack or Flutterwave payment
  pages, or Selar) and confirm current fees and payout terms on their own
  sites.
- **App store rules:** Apple treats tips for digital content or services as
  in-app purchases, and only the US storefront allows external payment
  links; a tip link has been rejected even there. So in the iOS build show
  the page's text and "ask the owner" with no payment link, and put the
  link only in Android, Windows and web builds (and on a web page you
  control). If the Android app ever goes to Google Play, check Play's
  payments policy the same way; sideloaded APKs for friends are not
  affected.

## Phase 6: Release to friends

1. Android: signed release APK shared directly (or Play internal testing).
2. iOS: TestFlight external group (needs Beta App Review and a demo
   account that sees only public-domain comics, per
   `docs/testflight-plan.md` section 6).
3. Web: PWA behind Caddy, same public origin as Komga and sync.
4. Feedback loop: friends use Report a problem; reports land in your sync
   DB and Diagnostics; "Copy report" turns any of them into a Claude task.

## Cloud sync recommendation

Keep using your own sync service for everyone, friends included. It only
stores small things (history, progress, collections, appearance, reader
settings, stats), so it costs almost nothing in disk or bandwidth, and it
already has per-user accounts. What fills drives is content, and that is
why downloads come first. Add per-user caps on the sync service (Phase 1),
and keep the existing backup export / import so anyone can carry their
data off your server. No third-party cloud is needed; if one is ever
wanted, add it as an optional backup target, not a replacement.

## Order of work at a glance

| Phase | Owner | Depends on |
|---|---|---|
| 0 Baseline and quick fixes | app | - |
| 1 Friend-ready accounts | app + sync-service | 0 |
| 2 Downloads first, honest status | app | 0 |
| 3 Native chrome | app | 0 |
| 4 Screen polish | app | 3 |
| 5 Support the server | app + web page | 1 |
| 6 Release to friends | ops | 1, 2 (3 and 4 can follow in updates) |
