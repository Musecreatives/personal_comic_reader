# Shaddai Reader

A Flutter comic/manga reader modeled on the iOS app Panels, targeting
Flutter web (PWA) first and iOS later from the same codebase. Talks to
self-hosted Komga and Kavita servers.

## Status

**Phase 1 of 5 complete**: project scaffold, backend adapter interface,
working Komga backend, server management UI, and library browsing.
See `CHANGELOG.md` for what's done per phase.

## Running

```bash
flutter pub get
flutter run -d chrome
```

On first launch you'll land on an empty state prompting you to add a
server. Add a Komga server pointed at your instance (e.g.
`http://100.108.109.63:8081`) with your Komga credentials.

## Building for web

```bash
flutter build web --release
```

Output lands in `build/web/`.

## Testing

```bash
flutter analyze
flutter test
```

## Architecture

- `lib/core/backend/` — the `ReaderBackend` interface and shared models.
  UI code only ever depends on this interface, never on a concrete
  backend or an HTTP client directly.
- `lib/backends/komga/`, `lib/backends/kavita/` — one implementation per
  server type. Kavita is a stub until Phase 3.
- `lib/core/storage/` — server configs and credentials (Hive +
  flutter_secure_storage, both web-safe).
- `lib/app/` — Riverpod providers, go_router routes, theme.
- `lib/features/` — one folder per screen/feature area.

## Known gaps after Phase 1

- Kavita backend is a stub (throws `BackendNotImplemented`) — lands in
  Phase 3.
- No reader screen yet — tapping a book shows a placeholder snackbar.
  Lands in Phase 2.
- App icons are the default Flutter placeholder icons; needs real
  branding art before shipping.
- `flutter analyze` should be run after any change and kept clean.
