# Manga brand, game landing page, app theme

Branch: `claude/manga-brand-game`. Brand approved 2026-10-25.

## Sources of truth

- `DESIGN.md`: tokens, rules, logo spec ("The Night Library").
- `docs/brand/brand-guide.html`: brand guide plus the landing page prototype (open in a browser; "Landing" and "Brand guide" switch views).
- Logo canvas (private, owner only): https://claude.ai/artifact/M9eersS1UMyxVE2BSnafxJ
- Brand guide (private, owner only): https://claude.ai/artifact/SBHd2uDuPSFzZqXcqV2nTh

## Decisions

- **Theme modes:** Midnight (navy, default), Washi (paper light, replaces `paper`), OLED black (`trueBlack`), and a new System mode. Saved values keep loading.
- **Colour roles:** violet is the accent for anything pressed, selected or tracked. Hanko red is seal ink only: logo, stamps, curtain, chapter marks, the cover corner mark. Danger is crimson, always shown with an icon and a label.
- **Accents:** Fuji violet (default), Ai indigo, Matcha, Yamabuki, Hanko. The old "danger" accent option is removed.
- **Type:** platform text faces stay. The brand mono is M PLUS 1 Code, replacing JetBrains Mono. The CJK display faces are used only at 40px and up.
- **Logo:** three manga panels ink in (読 Japanese, 읽 Korean, 读 Chinese), each bringing the name in its language (シャダイ リーダー, 샤다이 리더, 沙代阅读). The panels close into one hanko seal, which presses 読 as "Shaddai Reader" lands. It plays once on the splash screen in 2.4 s. At rest it's the pressed 読 seal. A native speaker still needs to check 沙代阅读.
- **Landing game:** stamp rally only. ドン, 쾅 and 砰 are hidden one per chapter and saved in the browser. The game never blocks a download.

## Phases

### Phase 0: housekeeping (done)
- [x] `.impeccable/config.json` and `design.json` committed; per-machine files ignored
- [x] This plan, CLAUDE.md
- [x] `claude/invites-and-phase2` pushed; PR #7

### Phase 1: brand spec (done)
- [x] DESIGN.md merged with the approved brand

### Phase 2: landing page
- [x] Port the prototype's landing view into `web/get/index.html`, with the script in `web/get/landing.js`. Keep the real download links, the `?code=` invite ticket and `TESTFLIGHT_URL`.
- [x] Noren curtain, chapters, toys, stamp rally, ink cursor, theme toggle (all in the prototype)
- [x] Load the Chinese display font with the Google Fonts `&text=` subset. Canvases pause off screen and run at 30 fps at most. Reduced motion means static.
- [ ] Check at 1101×688, 688×1101 and 390×844 (headless Chrome won't go below 512 px wide, so check phone width on a real phone)

### Phase 3: app theme (needs this PC for the tablet)
- [ ] `AppThemeMode`: add `system`; Washi values for `paper`; keep enum names so saved settings load
- [ ] `AccentOption`: replace `danger` with `hanko`, add Ai indigo, Matcha, Yamabuki values; unknown saved names fall back to violet
- [ ] `AppColors`: add `seal`, `sealText`, `onSeal`, `outline`; new danger crimson; Washi palette
- [ ] Mono to M PLUS 1 Code (`google_fonts`)
- [x] Splash: the logo sequence, played once; static seal with reduced motion
- [x] App icons and favicon from the logo canvas's Icons artboard
- [ ] `flutter analyze`, `flutter test`, tablet-size widget tests, then install on the real tablet

## Risks
- No Tailscale or adb in the cloud, so tablet checks stay local.
- CJK font weight on phones: subset web fonts and load the display faces lazily in the app.
- No real artwork. Covers are placeholders, and no library covers go on public pages.
