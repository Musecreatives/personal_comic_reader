# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users
The owner and a small circle of invited friends who read comics and manga from a self-hosted media server. They read mostly on a phone, one-handed, often in short sessions (in bed, commuting), and pick up where they left off. Each person has their own account, history and collections; the server itself is private (Tailscale), with a public address planned later.

## Product Purpose
Shaddai Reader is one reader for a self-hosted library. It puts Komga, Suwayomi (and OPDS sources) behind a single interface, remembers what each person is reading across devices, and gives the owner a few maintenance tools for the servers behind it. Success: opening the app and being back on the exact page within one tap, on any device.

## Positioning
A personal, multi-backend reader with cross-device continuity and server self-repair built in, rather than a viewer tied to a single server's own web UI.

## Operating Context
- Flutter web PWA (installed to the phone home screen) is the primary target; an Android APK and a Windows build share the same UI.
- Backends: Komga (main library), Suwayomi (online sources, source browsing, maintenance), OPDS; Kapowarr is a read-only status view. Kavita is retired.
- Served at reader.shaddai.home through Caddy over Tailscale; shaddai-sync (FastAPI + SQLite) provides login and syncs History, Collections, Appearance and Reader Settings.
- The reader supports single, double-page and vertical modes, LTR/RTL, per-series settings, downloads and bulk chapter actions.

## Capabilities and Constraints
- Continue reading is the core loop: Home hero, a persistent now-reading pill above the tab bar (hidden on Home), History, and resume-at-page.
- Five root tabs: Home, Search, Library, History, Settings; everything else is a full-screen sub-page.
- Undecided: public exposure at reader.shaddaicommunications.com; Stats and downloads are not yet synced.
- Terminology: "series" and "chapter" (Komga calls chapters "books").

## Brand Commitments
Name "Shaddai Reader" with the "SR" badge. The dark theme stays. The owner likes the iOS style of Paperback and Panels and wants the app to move that way: a dark, iOS-flavoured interface.

## Evidence on Hand
Paperback reference screenshots were provided by the owner earlier in the project (not stored in the repo). No testimonials, metrics or public users exist; none should be invented.

## Product Principles
1. Resume beats browse: the last-read chapter and page are always one tap away.
2. Phone and one thumb first; wider screens adapt from that, not the reverse.
3. The library and the reading are the content; interface chrome recedes, especially inside the reader.
4. Failures of the servers behind it are something the app can explain and help repair, not something the reader must diagnose alone.
5. Private by default: nothing is shared beyond invited accounts.

## Accessibility & Inclusion
No specific standard was set. Respect the system reduced-motion setting, keep text legible on the dark theme, and keep tap targets thumb-sized.
