---
name: Shaddai Reader
description: A night library for a self-hosted comic collection. Midnight navy, ink outlines, a hanko seal, and one brand in native chrome on iOS, Android, Windows and the web.
colors:
  midnight-page: "#0A1420"
  midnight-canvas: "#07101B"
  midnight-card: "#111F31"
  midnight-ink: "#F4F3F7"
  midnight-line: "rgba(143,193,232,0.2)"
  midnight-tone: "rgba(183,166,245,0.2)"
  violet: "#6E56CF"
  violet-text: "#B7A6F5"
  on-violet: "#FFFFFF"
  hanko: "#D23B3F"
  hanko-text: "#FF8588"
  on-hanko: "#FFF8F5"
  washi-page: "#F3F3F1"
  washi-card: "#E7E7E3"
  washi-strong: "#DADAD4"
  washi-ink: "#141519"
  washi-line: "rgba(20,21,25,0.16)"
  washi-violet: "#5B45B8"
  washi-violet-text: "#4F3AA8"
  washi-hanko: "#C9302F"
  washi-hanko-text: "#B3261E"
  oled-page: "#000000"
  danger: "#FF6F93"
  washi-danger: "#A3123F"
  warning: "#E0A24E"
  washi-warning: "#9A5B0A"
  komga: "#2E75C4"
  suwayomi: "#149E7C"
  kapowarr: "#C9821F"
typography:
  large-title:
    fontFamily: "platform (SF Pro / Roboto / Segoe UI Variable / Zen Kaku Gothic New on web)"
    fontSize: "30px"
    fontWeight: 700
    lineHeight: 1.05
    letterSpacing: "-0.6px"
  heading:
    fontFamily: "platform"
    fontSize: "20px"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "-0.4px"
  body:
    fontFamily: "platform"
    fontSize: "14px"
    fontWeight: 400
  mono:
    fontFamily: "M PLUS 1 Code, ui-monospace, monospace"
    fontSize: "11px"
    fontWeight: 500
  section-label:
    fontFamily: "M PLUS 1 Code, ui-monospace, monospace"
    fontSize: "10.5px"
    fontWeight: 500
    letterSpacing: "0.12em"
  display-jp:
    fontFamily: "Dela Gothic One, Hiragino Sans, Yu Gothic, sans-serif"
    fontWeight: 400
  display-kr:
    fontFamily: "Black Han Sans, Apple SD Gothic Neo, Malgun Gothic, sans-serif"
    fontWeight: 400
  display-cn:
    fontFamily: "Ma Shan Zheng, Kaiti SC, KaiTi, serif"
    fontWeight: 400
  wordmark:
    fontFamily: "Zen Kaku Gothic New, system-ui, sans-serif"
    fontWeight: 900
    letterSpacing: "-0.035em"
rounded:
  frame: "0px"
  seal: "0px"
  pill: "20px"
  nav: "26px"
  control-ios: "12px"
  control-android: "20px"
  control-windows: "4px"
  control-web: "10px"
  dialog-ios: "14px"
  dialog-android: "28px"
  dialog-windows: "8px"
  dialog-web: "16px"
spacing:
  gutter: "16px"
  page: "20px"
components:
  button-primary:
    backgroundColor: "{colors.midnight-ink}"
    textColor: "{colors.midnight-page}"
    height: "52px"
    padding: "0 24px"
  button-ghost:
    backgroundColor: "{colors.midnight-page}"
    textColor: "{colors.midnight-ink}"
    height: "52px"
    padding: "0 24px"
  seal:
    backgroundColor: "{colors.hanko}"
    textColor: "{colors.on-hanko}"
    rounded: "{rounded.seal}"
  progress-track:
    backgroundColor: "{colors.midnight-line}"
    height: "4px"
  progress-fill:
    backgroundColor: "{colors.violet}"
    height: "4px"
---

<!-- Approved 2026-10-25 from the brand guide and logo canvas. The tokens describe the target brand; lib/app/design_tokens.dart catches up in Phase 3. -->

# Design System: Shaddai Reader

## Overview

**Creative North Star: "The Night Library"**

Midnight shelves, ink outlines, and a seal stamped on every book. The chrome stays calm and dark so the pages are the light source. Structure is drawn, not shaded: ink lines frame things, screentone dots give texture, and a hanko seal says whose library this is. The same world runs on the landing page and in the app; the app wears it more quietly.

One brand runs everywhere, and the chrome around it (navigation, bars, sheets, dialogs, controls, transitions, text face) follows the platform it runs on, so the app feels native on iOS, Android, Windows and as an installed web app. See Platforms. The brand lives in colour, outline, metadata, the seal, and a few manga moments around reading. The reader screen itself carries none of it.

**Key Characteristics:**
- Midnight navy by default, paper (Washi) by day, OLED black for the dark, System to follow the device.
- Ink outlines at three weights carry structure; there are no soft shadows.
- Violet for what you touch; hanko red only as seal ink.
- Metadata in a CJK-capable mono; CJK display faces only in big moments.
- The logo is a seal that reads in three scripts.

## Colors

Cool navy surfaces, near-white ink, one violet accent and one red that is never a control.

### Primary
- **Library Violet** (violet, washi-violet on paper): anything you press, select or track. Primary-button offset shadow, selection, focus rings, progress fills, the active tab's bar. User-selectable (see Accent options).
- **Violet Ink** (violet-text, washi-violet-text): violet as text and on dark fills, where the base violet lacks contrast.

### Secondary
- **Hanko Seal** (hanko, washi-hanko): seal ink only. The logo, stamps, the landing page's noren curtain and chapter numbers, the corner mark on a placeholder cover, the empty-state glyph. Fixed whatever accent is picked.

### Neutral
- **Midnight Page / Canvas / Card** (midnight-page, midnight-canvas, midnight-card): page, the space behind the reader, raised surfaces. Unchanged from the old midnight theme so saved settings look the same.
- **Ink** (midnight-ink, washi-ink): text and outlines. White ink on Midnight, black ink on Washi. Secondary text is ink at 76% and 62%.
- **Line** (midnight-line, washi-line): hairlines inside lists, progress tracks.
- **Screentone** (midnight-tone): 1.2px dots on an 8px grid, for headers, empty states and the splash screen.
- **Washi Page / Card / Strong** (washi-page, washi-card, washi-strong): the light theme's ground, raised surfaces and canvas.
- **OLED Black** (oled-page): the pitch-black mode for reading in the dark.

### Status and identity
- **Danger** (danger, washi-danger): crimson, always paired with an icon and a label.
- **Warning** (warning, washi-warning): amber for "a server is down, nothing is wrong with you".
- **Source colours** (komga, suwayomi, kapowarr): fixed; they name an external service, never app chrome.

### Accent options
Five, as before: Fuji violet (default, `#6E56CF`), Ai indigo (`#2E5E9E`), Matcha (`#3D7A52`), Yamabuki (`#B87410`), Hanko (`#D23B3F`, turns the whole app red). The accent picker changes the violet role only. The old "danger" accent option is removed.

### Theme modes
Midnight (default), Washi, OLED black, System. Saved values keep loading: `midnight` and `trueBlack` as they are, `paper` as Washi. System is the one new mode.

### Named Rules
**The Seal Ink Rule.** Hanko red marks identity, never action. If a red thing can be tapped, it is wrong (the Hanko accent option is the user's explicit exception).

**The One Violet Rule.** Each screen gives violet to one action. Everything else is ink.

## Typography

**Text:** the platform face (SF Pro, Roboto, Segoe UI Variable; Zen Kaku Gothic New on the web)
**Mono:** M PLUS 1 Code (replaces JetBrains Mono, because it covers kana and kanji in series titles)
**Display:** Dela Gothic One (Japanese), Black Han Sans (Korean), Ma Shan Zheng (Chinese brush)

**Character:** native text you never notice, a mono that can spell 月の剣, and three display faces that each come from their own comics tradition.

### Hierarchy
- **Large title** (700, 30px, 1.05, -0.6px): root tab titles, in the platform face.
- **Heading** (700, 20px, 1.1): section and sheet titles.
- **Body** (400, 14px): everything else.
- **Mono** (500, 11px): every piece of metadata: chapter and page, sizes, counts, status words. Numbers that line up use it.
- **Section label** (500, 10.5px, 0.12em, uppercase mono): labels above groups. Sparingly.
- **Display** (CJK faces, 40px and up): large titles, empty states, loading and splash, and the landing page.

### Named Rules
**The Big Moments Rule.** CJK display faces appear only at 40px and up, in empty states, loading, splash and marketing. Never in lists, settings, controls or the reader.

## Layout

Five root tabs (Home, Search, Library, History, Settings) inside a persistent nav whose form is the platform's (see Platforms); all other screens are full-screen sub-pages. A now-reading pill floats above the nav (or over the foot of the content beside a rail or pane) on every tab except Home. Side gutter 16-20px. Breakpoints follow Material window size classes: compact below 600, expanded from 1008. Root tab content is capped at 1200px; some sub-pages still stretch on wide screens (known gap). Check every screen at tablet sizes (1101×688 and 688×1101) as well as on phones.

## Platforms
The style resolves from the device (`lib/app/platform_style.dart`) and can be forced per device in Settings > Appearance > Interface; the choice is never synced.

| | iOS / iPadOS | Android | Windows | Web (PWA) |
|---|---|---|---|---|
| Navigation | Floating frosted tab bar; sidebar from 900pt | M3 navigation bar; compact rail with the seal from 600dp | Fluent pane: compact icons below 1280px, expanded with labels above; Settings pinned to the foot | Navigation bar; rail from 600px; labelled sidebar from 1280px, Settings at the foot |
| Icons | SF-style (Cupertino) outline, filled when selected | Material outlined, filled when selected | Same as Android | Same as Android |
| Back | Circular glass chevron, swipe-back | Arrow icon button, predictive back gesture | Small square arrow button | Arrow icon button |
| Page transition | Slide with parallax | Predictive back | Fade forward | Fade forward |
| Touch feedback | Press-in scale, no ripple | Ink sparkle ripple | Hover and pressed fills | Hover and pressed fills |
| Sheets | Bottom sheet, 16 radius, grabber | Bottom sheet, 28 radius, grabber | Centred dialog | Bottom sheet on phones, centred dialog from 600px |
| Switches | iOS toggle | M3 switch | M3 switch | Follows the browser's OS |
| Density | Standard | Standard | Compact, visible scrollbars | Compact, visible scrollbars |
| Keyboard | - | - | Ctrl+1-5 tabs, Ctrl+F search | Ctrl+1-5 tabs, Ctrl+K / Ctrl+F search |
| Window | ProMotion enabled | Edge-to-edge, transparent system bars | Dark title bar tinted to the pane (#07101B, Windows 11) | Standalone, any orientation, iOS status bar translucent, viewport-fit cover |

The reader, covers, colours, the seal, source identity colours and mono metadata do not change between platforms.

## Elevation & Depth

Flat, drawn depth. Ink outlines separate surfaces; Paper 2 (card) lifts a surface by tone. iOS keeps its translucency where the platform expects it: the floating nav (radius 26, height 64) and the now-reading pill (radius 20, height 54) use a 24px backdrop blur over a 62-72% opaque card colour, edged in a 2px ink line. Rails, panes and the Material bar are solid canvas or card colour separated by a hairline.

### Named Rules
**The Drawn Depth Rule.** No soft drop shadows anywhere. The only offset shadow in the system is the violet one under a primary action (5px 5px, no blur), like a seal pressed off-register.

## Shapes

Three outline weights do the work: a 1px hairline for rows, dividers and app cards; a 2px control line for buttons, inputs, pills, covers and the tab bar's top edge; a 3px frame for manga panels on the landing page and the Home hero and empty states in the app. The seal is always a square, tilted 4° when it is large enough (48px and up). In the app, control and dialog corners follow the platform (`rounded` tokens); frames, covers and the seal stay square. On the landing page everything is square except speech bubbles.

## Components

### Buttons
- **Primary:** ink fill, paper text, 2px ink edge, violet offset shadow. Hover lifts 2px and grows the shadow; press pushes into it.
- **Ghost:** transparent with a 2px ink edge; hover fills with card colour.
- **In the app:** shapes follow the platform; the ink-and-violet colour assignment stays.

### Seal (logo mark)
A hanko-red square with 読 in Dela Gothic One, on-hanko ink. Clear space is a quarter of its width on every side. Minimum 16px; the lockup needs 150px of width. Below 64px the icon drops its screentone, below 48px its tilt; favicons are the bare seal edge to edge.

### Logo motion
Plays once per launch on the splash screen, 2.4s. Three manga panels ink in, right first: 読 (Japanese), 읽 (Korean), 读 (Chinese), 240ms each. As each lands, the wordmark shows the name in that language: シャダイ リーダー, 샤다이 리더, 沙代阅读. The gutters close in 300ms into one seal, which presses 読 (scale 1.7 to 1, a 12° turn, a 4° tilt) as "Shaddai Reader" lands at 1.4s. With reduced motion on, the pressed seal appears still. The rest state is always 読 and "Shaddai Reader". Reference: the logo canvas.

### Now-reading pill
Cover thumbnail, title, "CH. N · PAGE X OF Y" in mono, dismiss. Card colour, 2px ink edge (glass on iOS).

### Tab bar
Ink at 62% for inactive items; the active item is full ink with a 3px violet bar above its icon.

### Empty states
A 2px-framed block on screentone, a large CJK glyph in hanko red (空 for empty), a heading, one line of help and a ghost button.

### Errors
A 2px danger-coloured edge, an alert icon and a bold label in danger colour, then the plain-language fix in ink.

### Motion moments
Seal press (download finished, invite copied, series completed), tone swell (screentone tightens under a header as it scrolls away) and page turn (opening a chapter from Home). Everything else uses the platform's transitions.

## Do's and Don'ts

### Do:
- **Do** give each screen one violet action and keep hanko red for seals and marks.
- **Do** keep metadata in M PLUS 1 Code and everything else in the platform face.
- **Do** outline in ink and separate with space.
- **Do** pair danger colour with an icon and a label, every time.
- **Do** route new back buttons, sheets and switches through `AppBackButton`, `showAppSheet` and `Switch.adaptive` so they follow the platform; don't hard-code an iOS chevron or a bottom sheet.
- **Do** respect reduced motion: every manga moment becomes an instant change.

### Don't:
- **Don't** add soft drop shadows or gradients to chrome.
- **Don't** decorate the reader screen. The pages are the content.
- **Don't** use CJK display faces for body text, lists or controls.
- **Don't** recolour the seal, loop the logo animation in the app, or rest it on 읽 or 读.
- **Don't** put real covers from the library on public pages.
- **Don't** branch on `Platform.isX` in screens; read `PlatformStyle` so a forced interface style applies.
- **Don't** animate high-frequency actions, or let wide screens stretch phone layouts edge to edge.
