# Prompt: per-friend permissions, invites and requests

Paste everything below the line into a new local Claude Code session that
can reach both this repo (`personal_comic_reader`) and the sync service
(`~/docker/sync-service` on the home server).

---

Use `/ecc-plan` to plan this work, then `/ecc-orchestrate` to break the plan
into phases and run them one at a time. Stop after each phase for me to
check it on a device before the next one starts. Slow and careful beats
fast: nothing that works today may break.

## Context

- App: Shaddai Reader (Flutter), repo `personal_comic_reader`. Read
  `docs/testflight-plan.md` (roles, owner-only features, invite codes,
  quotas) and `docs/redesign-execution-plan.md` (Phase 1 and the rules at
  the top) first.
- Sync service: `~/docker/sync-service`, published at `/sync/*` behind
  Caddy. It already has `/auth/register`, `/auth/login`, bearer tokens,
  per-user resources and problem reports. The app's client is
  `lib/core/sync/sync_client.dart`.
- Design: the "Shaddai Reader Redesign" canvas, boards "Settings · Admin
  (you)" (People and Requests), "Settings · Friend" (Ask for a series, My
  requests) and "iOS · Search and add (admin)". Match them; keep today's
  Settings look (logo card, mono section labels, rows with icons and
  subtitles).

## What to build

1. **Roles.** `users.role` = `owner` | `member`; `/auth/me` returns it. The
   first account (mine) is `owner`. The app hides owner-only features for
   members (list in `docs/testflight-plan.md` section 3). Hiding is not the
   security boundary: Suwayomi, Kapowarr and Nextcloud stay unpublished.
2. **Invites.** Close open sign-up. Owner creates single-use invite codes
   (`POST /admin/invites`, list, revoke); `/auth/register` requires a valid
   code. App: Settings > People > Invite a friend shows a code and a share
   sheet message with the sync URL.
3. **Per-friend permissions** (owner sets, stored per member):
   `can_download` (default true), `max_concurrent_downloads` (default 2),
   `can_request` (default true). `GET/PATCH /admin/members/:id`. The app
   reads its own permissions from `/auth/me` and enforces them in the
   download manager and the Search / Settings UI.
4. **Requests.** Members can ask for a series: `POST /requests` (title,
   optional note, optional ComicVine id), `GET /requests` (own), owner
   `GET /admin/requests` and `PATCH` to `added` | `declined` with an
   optional note. Rate-limit per member (e.g. 10 per day). App: friend
   "Ask for a series" sheet and "My requests" list with Waiting / Added /
   Declined; owner Settings > Requests with a badge, and from a request a
   one-tap jump into the existing Kapowarr add flow
   (`lib/features/search/acquire_search.dart`) pre-filled with the title.
5. **Quotas and limits** from `docs/testflight-plan.md` section 2 (records
   per resource, problem reports per day and size).

## Constraints

- Do not remove or rename any existing feature, route, stored field or
  sync resource. Migrations must be additive and reversible.
- Owner experience is unchanged except for the new People and Requests
  rows.
- Every new server endpoint has tests; every new app screen has a widget
  test; `flutter analyze` clean and `flutter test` green at the end of each
  phase.
- No secrets in the repo or in logs; Diagnostics must keep skipping
  `/auth/` bodies.
- Work on a branch, open a PR per phase, and do not merge without me.

## Done when

On a clean device, a friend uses an invite code, sees only Komga, reads,
downloads (respecting their cap), asks for a series; I see the request
under Settings > Requests, add it through Kapowarr, and the friend sees it
change to Added.
