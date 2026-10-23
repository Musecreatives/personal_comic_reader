# Prompt: execute the native redesign

Paste everything below the line into a new local Claude Code session in the
`personal_comic_reader` repo, with the Android tablet connected over USB.

---

Use `/ecc-plan` to turn `docs/redesign-execution-plan.md` into a concrete
plan for this codebase, then `/ecc-orchestrate` to run it phase by phase.
Slow burn: finish one phase, stop, and wait for me to try it on my devices
before starting the next.

## Read first

- `docs/redesign-execution-plan.md`: the phases, the rules at the top, the
  test devices and what "done" means for each phase.
- `DESIGN.md`: tokens and the Platforms section.
- `docs/testflight-plan.md`: roles, owner-only features, release steps.
- The "Shaddai Reader Redesign" canvas: the "Today" rows are the app as it
  is now; every other board shows the same layout made native. Match the
  boards; do not invent new layouts.
- Branch `claude/loving-ritchie-f0lwy5`: a first pass at platform chrome
  (`lib/app/platform_style.dart`, `lib/features/shared/glass_bottom_nav.dart`,
  `lib/features/shared/app_sheet.dart`, `lib/features/shared/back_button.dart`).
  Phase 0 reviews it against the canvas; keep what matches.

## Non-negotiables

- No feature removed or renamed, especially owner and dev features
  (Kapowarr, Suwayomi maintenance, media pool, diagnostics, debug mode).
- Today's layouts stay: Home hero and shelves, Series header with stats
  row and "CH n" rows, Library chips and grid, Settings rows with icons,
  the reader's page footer.
- The bundled app icon and series metadata always show.
- Downloads first for friends.
- Page turns and keyboard shortcuts never animate; Reduce Motion respected.
- `flutter analyze` clean and `flutter test` green at the end of every
  phase; add widget tests for new screens and states; run on the Android
  tablet (portrait and landscape) and one phone before calling a phase done.
- One PR per phase; never merge without me.

## Start with

Phase 0 step 1: the web start-up crash in
`lib/core/stats/reading_stats_store.dart` (`Random().nextInt(1 << 32)`
throws on the web because `1 << 32` is 0). Fix it with a test, then
continue with the rest of Phase 0.

Phase 1 item 4 (permissions, invites, requests) has its own prompt in
`docs/prompts/permissions-invites-requests.md`; run it in a separate
session if the sync-service work is easier there.
