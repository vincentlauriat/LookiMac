# Looki pour Mac — Design Spec

Date: 2026-09-05
Status: approved by Vincent (chat, 2026-09-05)

## 1. Goal

A native macOS app to browse, search and archive the moments captured by a
Looki L1 wearable camera, using the read-only Looki Open API
(`https://open.looki.ai/api/v1`). Three equal use cases in v1:

1. **Review a day** — calendar → timeline of moments → video + description.
2. **Find a memory** — semantic search across all moments.
3. **Archive on demand** — download a day's media and generate a Markdown
   journal into a user-chosen folder.

Non-goals for v1: device control (not exposed by the API), offline full
index, Sparkle auto-update, iOS.

## 2. Constraints and decisions

| Topic | Decision |
|---|---|
| Platform | macOS 26 only, SwiftUI, Swift 6 strict concurrency |
| Project generation | xcodegen (`project.yml`), like HealthCheck |
| App name / bundle id | Looki pour Mac / `fr.lauriat.lookimac` |
| Persistence | Light cache (metadata JSON + thumbnails). No database. |
| Secrets | API key in the login Keychain (Security framework). Never in UserDefaults, plist or repo. Optional one-time import from `~/.config/looki/credentials.json` in Settings. |
| Delivery | Signed + notarized DMG via `Scripts/release.sh` (copied from HealthCheck, Sparkle parts removed). Artifacts in `release/`. |
| Language | UI strings French; code and docs English. |

## 3. Known API surface (verified 2026-09-05)

Auth header: `x-api-key: <key>`. Envelope: `{ "code": Int, "detail": String, "data": T? }`,
`code == 0` means success. Missing header → HTTP 422. Rate limit → HTTP 429.

| Endpoint | Purpose | Notes |
|---|---|---|
| `GET /me` | Account profile | `data.user {id, first_name, last_name, tz, gender, birthday}` |
| `GET /moments?on_date=YYYY-MM-DD&need_adjacent_date=true` | Moments of a day | `data` is an array of `Moment`. Param name found in web.looki.ai bundle. |
| `GET /moments/{moment_id}` | Moment detail | Includes `cover_file.file.temporary_url` (signed, expiring) |
| `GET /moments/search?query=...` | Semantic search | `data {items: [Moment], has_more: Bool}`; pagination param to confirm (`cursor`/`page`) |

`Moment` fields: `id`, `title`, `description`, `media_types` (`VIDEO`, `IMAGE`),
`cover_file {id, file {temporary_url, media_type, metadata {width, height, duration_ms}}, location, created_at, tz}`,
`date`, `tz`, `start_time`, `end_time`. `location` is a JSON **string**
(`{street, locality, administrativeArea, isoCountryCode, subLocality?}`) and is
decoded in a second pass. Per-moment file lists beyond `cover_file` are to be
confirmed from the detail endpoint during implementation.

Web-app-only routes (`/moments/by-cursor`, `/moments/monthly-calendar`) are **not**
available on the open API; the month calendar is built client-side.

## 4. Architecture

Two xcodegen targets plus tests:

```
LookiMac.xcodeproj
├── LookiKit        (framework, macOS 26)   — no UI, fully testable with swift test
├── LookiKitTests   (unit tests, fixtures)
└── LookiMac        (SwiftUI app)           — views, view models, Keychain, settings
```

### 4.1 LookiKit

- **`LookiClient`** (`actor`) — `me()`, `moments(on: Date, timeZone:)`,
  `moment(id:)`, `search(query:, cursor:)`. Injected `URLSession` and base URL.
  Decodes the envelope; `code != 0` → `LookiError.api(code, detail)`.
  Errors: `.unauthorized`, `.rateLimited(retryAfter: TimeInterval?)`, `.network`,
  `.decoding`, `.api`. No silent nil `data`.
- **Models** — `Moment`, `MomentFile`, `FileMetadata`, `Location`, `UserProfile`,
  `SearchPage`. `Codable`, `Sendable`, `Identifiable`.
- **`MomentCache`** — per-day JSON under
  `~/Library/Caches/fr.lauriat.lookimac/days/YYYY-MM-DD.json`, thumbnails under
  `thumbs/<file_id>.jpg`. Signed video URLs are never cached; the detail endpoint
  is re-queried at playback time. `purge()` clears everything.
- **`JournalRenderer`** — pure function `[Moment] → Markdown String`, same layout
  as `journal/2026-09-05.md` (header, chronology table, narrative, footer).
- **`DayArchiver`** — for a date and a destination root: creates
  `<root>/YYYY/MM/DD/`, downloads each moment's media (via fresh detail calls),
  writes `journal.md` and `moments.json`. Reports progress via `AsyncStream`.
  Skips files already present with matching size.

### 4.2 LookiMac (app)

Three-column `NavigationSplitView`:

- **Sidebar** — month calendar. Days with moments are marked; marks come from the
  cache first, then background fetches for the visible month (one call per day,
  throttled). Month navigation, "today" button.
- **Content** — timeline of the selected day: cards with time range, title,
  street, thumbnail, media badges. When the toolbar search field is active, the
  column shows search results instead, paginated with `has_more`.
- **Detail** — `AVPlayer` on the fresh signed URL, full description, address,
  start/end, "Reveal in archive" when the day is archived.
- **Toolbar** — search field, "Archiver ce jour", "Ouvrir le dossier d'archive".
- **Settings** — API key (Keychain) with "Tester la connexion" (`/me`), archive
  folder (security-scoped bookmark), cache purge, import from
  `~/.config/looki/credentials.json`.

State: one `@Observable` `AppModel` owning the client, cache and selection;
per-screen view models kept small. All API work off the main actor.

## 5. Error handling and edge cases

| Situation | Behaviour |
|---|---|
| No API key | Settings opens on launch with an explanatory banner. |
| 422 / 401 (bad key) | Persistent banner "Clé API refusée", link to Settings. |
| 429 | Requests queued and retried after `Retry-After` (or 5 s); banner while waiting. Never hammer. |
| Network down | Show cached day if any, banner otherwise; retry button. |
| Empty day | Clear empty state ("Aucun moment ce jour"). |
| Expired signed URL | Detail re-fetched automatically once; then error in the player. |
| Archive folder unavailable | Ask to choose again; never write elsewhere silently. |

## 6. Testing

- `LookiKitTests` on real, anonymised fixtures captured 2026-09-05
  (`me.json`, `moments-day.json`, `moment-detail.json`, `search.json`,
  `error-422.json`).
- `LookiClient` tested with a `URLProtocol` stub: headers, envelope decoding,
  each error path, 429 mapping.
- `JournalRenderer` golden test against a fixture rendering.
- `DayArchiver` tested against a temporary directory with stubbed downloads.
- App: manual smoke test per release; `xcodebuild build` mandatory after every
  change.

## 7. Delivery

- `Scripts/release.sh` adapted from HealthCheck (no Sparkle), notary profile
  `AppliMacVincentGithub`, output in `release/`.
- `.gitignore`: doc journals (`COMMANDS.md`, `MEMORY.md`, `CHANGES.md`,
  `TODOS.md`, `PLAN.md`), `.omc/`, `build/`, `release/`, `*.dmg`, `*.xcodeproj`
  (generated), `journal/` (personal data).
- Repo on GitHub later, feature branches only, no direct push to `main`.

## 8. Out of scope / later

Sparkle updates, iOS companion, local full-text index (SwiftData), automatic
nightly archiving, CLI target reusing LookiKit.
