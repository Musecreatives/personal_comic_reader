# Changelog

## Phase 1 — Scaffold, backend adapter, Komga auth + library browse

- Project scaffolded for web + iOS targets (Windows dev machine, no iOS
  toolchain here — iOS build deferred to Codemagic/Mac per project
  context).
- `ReaderBackend` abstract interface defined in `lib/core/backend/`,
  covering auth, libraries, series, books, pages, progress, continue
  reading, recently added, collections, and read lists.
- `KomgaBackend` implemented against the live Komga REST v1 API
  (endpoints and response shapes verified against a running instance
  at `100.108.109.63:8081`, not guessed from docs).
- `KavitaBackend` stub — throws `BackendNotImplemented` on every method;
  exists so the server-type selector works without crashing. Real
  implementation is Phase 3.
- Server management: add/edit/delete servers, test-connection button,
  select active server. Configs in Hive, passwords in
  `flutter_secure_storage` (web-safe via its bundled IndexedDB/WebCrypto
  backend — no shared_preferences fallback needed).
- Screens: `/home` (continue reading + recently added rows, library
  shortcuts), `/library/:id` (paginated series grid/list, sort, search,
  unread filter), `/series/:id` (cover, summary, book list with
  progress), `/settings`, `/settings/servers`.
- Dark theme by default; wide-screen two-column layout on series detail.
- `RetryInterceptor` added to dio: retries 5xx/timeout/connection errors
  up to twice with backoff; never retries 4xx.
- Tests: `KomgaBackend` unit tests against a mocked dio adapter
  (auth success/failure, library/series parsing incl. the Spring
  Pageable envelope and title fallback, progress update, thumbnail URL
  building) and a widget test asserting the library grid renders one
  tile per series with correct unread badges.
- PWA manifest and `index.html` updated with the app's actual name,
  description, and dark theme color (icons still placeholders — no
  branding art yet).

### Known Komga API field mismatches vs. the original plan

None found — every endpoint listed in the Phase 1 prompt (`/api/v1/series/list`,
`/api/v1/books/ondeck`, `/api/v1/books/latest`, `/api/v1/books/{id}/pages/{n}`,
`/api/v1/books/{id}/read-progress`, thumbnail routes) was verified against
the live OpenAPI spec and matches exactly.

### Stubbed / deferred

- Kavita backend (Phase 3).
- Reader screen itself — `/series/:id` book taps currently show a
  placeholder snackbar (Phase 2).
- Collections/read lists have data-layer support but no dedicated
  screens yet (Phase 3 per the original plan).
