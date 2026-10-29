# Shaddai Reader

A comic and manga reader for your own self-hosted library. One Flutter
codebase ships to **iOS, Android, Windows and the web**, with native-feeling
navigation and chrome on each platform.

[![CI](https://github.com/Musecreatives/personal_comic_reader/actions/workflows/ci.yml/badge.svg)](https://github.com/Musecreatives/personal_comic_reader/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/Musecreatives/personal_comic_reader)](https://github.com/Musecreatives/personal_comic_reader/releases/latest)

## Features

- **Bring your own server**: Komga, Kavita and Suwayomi, plus any generic
  OPDS 1.2 (with page streaming) catalog. A read-only Kapowarr status view
  is included.
- **A full reader**: single page, double page and vertical scroll modes,
  zoom, and an experimental smart panel view.
- **Offline first**: downloads with a Wi-Fi-only queue; downloaded pages are
  always preferred over the network.
- **Many sources, one series**: link the same series across servers and fall
  back to the best backup source (up to date, on time, fewest gaps).
- **Search across servers**, an updates feed, collections and read lists.
- **Local reading stats** (pages, time, streak). They stay on your device
  and are never sent anywhere.
- **Adaptive UI**: iPhone, iPad, Android phone and tablet, Windows desktop
  and the web, each following its own platform's conventions. You can force
  an interface style per device in Settings.

## Download

Grab the latest build for your platform from the
[Releases page](https://github.com/Musecreatives/personal_comic_reader/releases/latest):

| Platform | File |
|---|---|
| Android | `ShaddaiReader.apk` |
| Windows | `ShaddaiReader-windows.zip` |
| Web (self-host) | `ShaddaiReader-web.zip` |
| iOS | `ShaddaiReader-unsigned.ipa` (sideload), or TestFlight |

## Getting started

1. Install or open the app.
2. On first launch you land on an empty state: tap **Add a server** and
   enter the address of your Komga, Kavita, Suwayomi or OPDS instance, for
   example `http://192.168.1.50:25600`, with your login.
3. Your libraries appear. Pick a series and start reading.

To reach a home server while away, put it behind HTTPS or use a private
network such as [Tailscale](https://tailscale.com/download).

## Build from source

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install)
(stable channel).

```bash
flutter pub get
flutter run -d chrome        # or: -d windows, -d <device id>
```

Release builds:

```bash
flutter build web --release
flutter build apk --release
flutter build windows --release
flutter build ios --release --no-codesign   # needs a Mac with Xcode
```

### Self-hosting the web build

Serving the web app from the same origin as your server (behind a reverse
proxy such as Caddy or nginx) avoids the CORS block a browser hits when it
talks to a bare server address, since Komga does not send
`Access-Control-Allow-Origin`. Build with `--base-href /`, serve
`build/web/`, and proxy your server under a path such as `/komga` on the
same host.

## Testing

```bash
flutter analyze
flutter test
```

Every pull request runs both in CI. Pushing a `v*` tag builds every platform
and publishes a GitHub Release.

## Architecture

- `lib/core/backend/`: the `ReaderBackend` interface and shared models. UI
  code only depends on this interface, never on a concrete backend or an
  HTTP client.
- `lib/backends/{komga,kavita,suwayomi,opds}/`: one implementation per
  server type. Entity IDs are opaque strings to the UI; OPDS uses full feed
  URLs, so every navigation call site `Uri.encodeComponent`s the ID before
  putting it in a route path.
- `lib/core/downloads/`: the download queue and offline-first page
  resolution.
- `lib/core/panels/`: the experimental smart panel detector, a pure
  geometry function over an RGBA buffer.
- `lib/core/stats/`: local-only reading stats.
- `lib/core/storage/`: server configs, credentials and the last-visited
  route (Hive and flutter_secure_storage, both web-safe).
- `lib/app/`: Riverpod providers, go_router routes, theme, platform style.
- `lib/features/`: one folder per screen or feature area.
- `web/get/`: the static download/landing page.

What shipped in each release is in [CHANGELOG.md](CHANGELOG.md).

## Known gaps

- OPDS-PSE page streaming is verified for routing, auth and parsing but not
  against a large populated library.
- The smart panel view is a simple gutter-variance heuristic. It gets
  non-grid layouts, bleeds and borderless panels wrong, so it is opt-in.
- iOS builds are unsigned unless you provide your own signing setup.

## Contributing

Issues and pull requests are welcome. Before opening a PR, run
`flutter analyze` and `flutter test`, and check any UI change at phone and
tablet sizes (for example 1101x688 and 688x1101). Use `PlatformStyle`
instead of `Platform.isX`, and the shared `AppBackButton`, `showAppSheet`
and `Switch.adaptive` widgets.

## License

Licensed under the [Apache License 2.0](LICENSE). The software is provided
"as is", without warranty of any kind. The Shaddai name and logo are not
covered by the license (see [NOTICE](NOTICE)).
