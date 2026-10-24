---
name: Shaddai Reader
description: Dark, navy-and-violet reader for a self-hosted comic library, one brand in native chrome on iOS, Android, Windows and the web.
colors:
  page: "#0A1420"
  canvas: "#07101B"
  card: "#111F31"
  border: "#1E3350"
  border-strong: "#223349"
  text: "#F4F3F7"
  text-alt: "#F3F6FA"
  accent: "#6E56CF"
  accent-link: "#8F7BEA"
  accent-soft: "#B7A6F5"
  fill-tint: "#8FC1E8"
  komga: "#2E75C4"
  suwayomi: "#149E7C"
  kapowarr: "#C9821F"
  danger: "#D8455F"
typography:
  large-title:
    fontFamily: "platform (SF Pro / Roboto / Segoe UI Variable / Inter on web)"
    fontSize: "30px"
    fontWeight: 700
    lineHeight: 1.05
    letterSpacing: "-0.6px"
  heading:
    fontFamily: "Inter"
    fontSize: "20px"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "-0.4px"
  body:
    fontFamily: "Inter"
    fontSize: "14px"
    fontWeight: 400
  mono:
    fontFamily: "JetBrains Mono"
    fontSize: "11px"
    fontWeight: 500
  section-label:
    fontFamily: "JetBrains Mono"
    fontSize: "9.5px"
    fontWeight: 500
    letterSpacing: "1.4px"
rounded:
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
---

# Design System: Shaddai Reader

## Overview
A dark, content-first reader. Navy surfaces with a single violet accent, mono metadata (counts, sizes, status) against each platform's own text face. The library and the pages are the content; chrome should recede. One brand runs everywhere; the chrome around it (navigation, bars, sheets, dialogs, controls, transitions, type) follows the platform it runs on, so the app feels native on iOS, Android, Windows and as an installed web app. See Platforms.

## Colors
- **Surfaces:** page `#0A1420`, canvas `#07101B` (behind the reader), card `#111F31`, 1px borders `#1E3350`.
- **Text:** `#F4F3F7` primary, with 60/45/42/30% alpha steps of `#F3F6FA` for secondary text.
- **Accent:** violet `#6E56CF`; link `#8F7BEA` and soft `#B7A6F5` are lighter derivations. The accent is user-selectable (five options) and the theme has three modes: midnight (default), true black, paper (light).
- **Source identity colors** are fixed and mark external services, not app chrome: Komga blue, Suwayomi green, Kapowarr amber.
- **Danger** `#D8455F`. Progress tracks and hover fills are 6-18% tints of `#8FC1E8`.

## Typography
JetBrains Mono for every piece of metadata and section label (9.5px, uppercase, wide tracking) on every platform; it is the brand's typographic signature. Text and titles use the platform face: SF Pro on iOS (bold, tight large titles), Roboto on Android (medium-weight, untracked headlines), Segoe UI Variable on Windows (semibold titles), Inter on the web, where no system face is guaranteed. Numbers that line up use the mono face.

## Layout
Five root tabs (Home, Search, Library, History, Settings) inside a persistent nav whose form is the platform's (see Platforms); all other screens are full-screen sub-pages. A now-reading pill floats above the nav (or over the foot of the content beside a rail or pane) on every tab except Home. Side gutter 16-20px. Breakpoints follow Material window size classes: compact below 600, expanded from 1008. Root tab content is capped at 1200px; some sub-pages still stretch on wide screens (known gap).

## Platforms
The style resolves from the device (`lib/app/platform_style.dart`) and can be forced per device in Settings > Appearance > Interface; the choice is never synced.

| | iOS / iPadOS | Android | Windows | Web (PWA) |
|---|---|---|---|---|
| Navigation | Floating frosted tab bar; sidebar from 900pt | M3 navigation bar; compact rail with the mascot from 600dp | Fluent pane: compact icons below 1008px, expanded with labels above; Settings pinned to the foot | Navigation bar; rail from 600px; labelled sidebar from 1008px, Settings at the foot |
| Icons | SF-style (Cupertino) outline, filled when selected | Material outlined, filled when selected | Same as Android | Same as Android |
| Back | Circular glass chevron, swipe-back | Arrow icon button, predictive back gesture | Small square arrow button | Arrow icon button |
| Page transition | Slide with parallax | Predictive back | Fade forward | Fade forward |
| Touch feedback | Press-in scale, no ripple | Ink sparkle ripple | Hover and pressed fills | Hover and pressed fills |
| Sheets | Bottom sheet, 16 radius, grabber | Bottom sheet, 28 radius, grabber | Centred dialog | Bottom sheet on phones, centred dialog from 600px |
| Switches | iOS toggle | M3 switch | M3 switch | Follows the browser's OS |
| Density | Standard | Standard | Compact, visible scrollbars | Compact, visible scrollbars |
| Keyboard | - | - | Ctrl+1-5 tabs, Ctrl+F search | Ctrl+1-5 tabs, Ctrl+K / Ctrl+F search |
| Window | ProMotion enabled | Edge-to-edge, transparent system bars | Dark title bar tinted to the pane (#07101B, Windows 11) | Standalone, any orientation, iOS status bar translucent, viewport-fit cover |

The reader, covers, colours, source identity colours and mono metadata do not change between platforms.

## Elevation & Depth
Depth comes from translucency, not shadows: the iOS nav (radius 26, height 64) and the now-reading pill (radius 20, height 54) use a 24px backdrop blur over a 62-72% opaque card colour and a 60% border. Rails, panes and the Material bar are solid canvas or card colour separated by a 1px hairline.

## Shapes
Corner radii follow the platform (see the `rounded` tokens): generous on iOS and Android, 4px controls and 8px dialogs on Windows, in between on the web. iOS primary buttons are fully rounded. Cards keep 1px hairline borders everywhere.

## Components
Glass nav bar; now-reading pill (title, "Ch. N · page X of Y", dismiss); Home hero with resume; horizontal "also in progress" shelf; series cards with placeholder gradient covers; bottom sheets for chapters and reader settings; status pills per backend.

## Do's and Don'ts
- Do keep metadata in mono and everything else in Inter or the large title.
- Do keep the violet accent as the one emphasis colour; source colours are for service identity only.
- Don't add drop shadows; use translucency and hairlines.
- Don't animate high-frequency actions; respect reduced motion.
- Don't let wide screens stretch phone layouts edge to edge.
- Do route new back buttons, sheets and switches through `AppBackButton`, `showAppSheet` and `Switch.adaptive` so they follow the platform; don't hard-code an iOS chevron or a bottom sheet.
- Don't branch on `Platform.isX` in screens; read `PlatformStyle` so a forced interface style applies.
