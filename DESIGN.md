---
name: Shaddai Reader
description: Dark, navy-and-violet reader for a self-hosted comic library, moving toward an iOS (Paperback/Panels) feel.
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
    fontFamily: "SF Pro Text, Roboto, sans-serif"
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
spacing:
  gutter: "16px"
  page: "20px"
---

# Design System: Shaddai Reader

## Overview
A dark, content-first reader. Navy surfaces with a single violet accent, mono metadata (counts, sizes, status) against Inter and an iOS-style large title. The library and the pages are the content; chrome should recede. The owner wants the app to move toward the iOS look of Paperback and Panels (frosted translucent bars, large titles, generous rounding) while staying dark. The values below record what ships today; the redesign will revise them here.

## Colors
- **Surfaces:** page `#0A1420`, canvas `#07101B` (behind the reader), card `#111F31`, 1px borders `#1E3350`.
- **Text:** `#F4F3F7` primary, with 60/45/42/30% alpha steps of `#F3F6FA` for secondary text.
- **Accent:** violet `#6E56CF`; link `#8F7BEA` and soft `#B7A6F5` are lighter derivations. The accent is user-selectable (five options) and the theme has three modes: midnight (default), true black, paper (light).
- **Source identity colors** are fixed and mark external services, not app chrome: Komga blue, Suwayomi green, Kapowarr amber.
- **Danger** `#D8455F`. Progress tracks and hover fills are 6-18% tints of `#8FC1E8`.

## Typography
Inter for text, JetBrains Mono for every piece of metadata and section label (9.5px, uppercase, wide tracking), and an iOS-style large title (SF Pro where available, else Roboto) for hero titles. Numbers that line up use the mono face.

## Layout
Five root tabs (Home, Search, Library, History, Settings) inside a persistent floating glass nav; all other screens are full-screen sub-pages. A now-reading pill floats above the nav on every tab except Home. Side gutter 16-20px. Phone-first; wider screens currently stretch rather than re-lay-out (known gap).

## Elevation & Depth
Depth comes from translucency, not shadows: the nav (radius 26, height 64) and the now-reading pill (radius 20, height 54) use a 24px backdrop blur over a 62-72% opaque card colour and a 60% border.

## Shapes
Rounded throughout: 26px floating nav, 20px pill, fully rounded primary buttons, cards with 1px hairline borders.

## Components
Glass nav bar; now-reading pill (title, "Ch. N · page X of Y", dismiss); Home hero with resume; horizontal "also in progress" shelf; series cards with placeholder gradient covers; bottom sheets for chapters and reader settings; status pills per backend.

## Do's and Don'ts
- Do keep metadata in mono and everything else in Inter or the large title.
- Do keep the violet accent as the one emphasis colour; source colours are for service identity only.
- Don't add drop shadows; use translucency and hairlines.
- Don't animate high-frequency actions; respect reduced motion.
- Don't let wide screens stretch phone layouts edge to edge.
