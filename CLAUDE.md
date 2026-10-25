# Shaddai Reader

Flutter comic/manga reader for a self-hosted library (Komga, Kavita, Suwayomi), shipped to iOS, Android, Windows and the web. The landing page lives in `web/get/`.

- **Design:** follow `DESIGN.md`. The current brand work is tracked in `docs/plans/manga-brand-and-landing-game.md`.
- **Tablet testing:** check every UI change at tablet sizes (1101×688 and 688×1101) as well as phone, and install on the real tablet before calling it done.
- **No server access from the cloud:** the home server and the tablet are only reachable from the owner's PC (Tailscale, adb). Cloud sessions must not try to reach them; leave those steps for a local session.
- **Platform rules:** read `PlatformStyle` instead of `Platform.isX`; use `AppBackButton`, `showAppSheet` and `Switch.adaptive`.
- **Checks:** `flutter analyze` and `flutter test` before committing.
