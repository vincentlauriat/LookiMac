# Journal — Design Spec

Date: 2026-09-05
Status: approved by Vincent (chat, 2026-09-05)
Extends: `2026-09-05-looki-pour-mac-design.md` (v0.1)

## 1. Goal

Bring the **Journal** section of the Looki iPhone app to Looki pour Mac: the chronological
feed of AI-generated posts Looki produces from a day's moments (diary captions with a
generated image, comic page, daily vlog, daily health report, yesterday's recap), browsable
by day, readable in full, and included in the day archive.

Non-goals: creating/editing/deleting posts (API is read-only), reactions, sharing, the
"Loom"/studio features of the web app.

## 2. Data source (verified 2026-09-05 against the live API)

`GET /journals` → `data { items: [JournalDay], next_cursor_id: String?, has_more: Bool }`,
newest day first. `JournalDay { date: "YYYY-MM-DD", journals: [JournalPost] }`.

`JournalPost` fields:

| Field | Type | Notes |
|---|---|---|
| `id` | String | UUID |
| `type` | String | `DIARY`, `COMIC_PAGE`, `DAILY_VLOG`, `DAILY_HEALTH_REPORT`, `YESTERDAY_RECAP`, `SYSTEM_POST`; unknown values must decode to `.unknown(raw)` |
| `title` | String? | absent on DIARY |
| `description` | String? | short caption (DIARY) or 1-paragraph summary (others) |
| `content` | String? | **Markdown** body (`###` headings, `-` bullets, `![alt](url)` images, bold, `↓` lines). Present on YESTERDAY_RECAP and SYSTEM_POST |
| `start_date` | String? | COMIC_PAGE only (the day the comic covers) |
| `media_items` | [`{ source: RemoteFile, thumbnail: RemoteFile? }`] | DIARY/COMIC_PAGE/SYSTEM_POST: one IMAGE; DAILY_VLOG: one VIDEO (portrait 720×1280) with IMAGE `thumbnail`; reports/recap: empty |
| `date`, `tz` | String | day of the post and its offset |
| `recorded_at`, `created_at` | ISO date | `recorded_at` orders posts within a day |

`GET /journals/{id}` returns the same object. Pagination: `next_cursor_id` is a date string;
the **request parameter name is unverified** (only two days of data exist). The client sends
`cursor_id=<next_cursor_id>`; if the API ignores it (same first page returned), the loader
stops instead of looping. To be re-checked once `has_more` is `true` in real data.

`temporary_url` values are signed and expiring — same rules as moments: never cached on disk,
re-fetched via `GET /journals/{id}` before playback/download.

## 3. Decisions

- **Placement:** a `Moments | Journal` segmented picker at the top of the sidebar. Journal mode
  turns the content column into the feed and the detail column into the post view. The
  calendar stays; clicking a day scrolls the feed to that day's section.
- **Types shown:** all except `SYSTEM_POST` (Looki announcements), hidden by default; a
  Settings toggle "Afficher les annonces Looki" (UserDefaults `showSystemPosts`) reveals them.
  Unknown types are shown with their raw name as badge, never dropped, never crash.
- **Markdown rendering:** in-house block renderer (no WebKit, no dependency): headings
  (`#`…`###`), bullet lists (`-`, `*`), images (`![alt](url)`), horizontal rule (`---`),
  paragraphs; inline bold/italic/links through `AttributedString(markdown:)`. Anything
  unrecognised renders as a paragraph.
- **Archive:** "Archiver ce jour" also downloads the day's journal media into
  `YYYY/MM/DD/journal/` named `<type-lowercase>-<HHmm>-<id8>.<ext>` (vlog thumbnails are not
  downloaded), and `journal.md` gains a final section `## Journal Looki` listing each post
  (time · type badge · title, caption, then raw Markdown content). `SYSTEM_POST` is never
  archived. `moments.json` is unchanged; a sibling `journals.json` holds the raw posts
  (signed links stripped).
- **Cache:** per-day file `journals/YYYY-MM-DD.json` in the existing cache root, stripped of
  signed URLs. The feed loads from cache first, then refreshes from the API.
- **Language:** UI French; type labels: Diary → « Journal », COMIC_PAGE → « BD »,
  DAILY_VLOG → « Vlog », DAILY_HEALTH_REPORT → « Santé », YESTERDAY_RECAP → « Récap »,
  SYSTEM_POST → « Looki ».

## 4. Architecture

### 4.1 LookiKit additions
- `JournalPost`, `JournalMedia`, `JournalDay`, `JournalPage`, `JournalType` (RawRepresentable
  enum with `.unknown(String)`, `var label: String` French, `var fileStem: String`).
- `LookiClient.journals(cursor: String? = nil) async throws -> JournalPage`,
  `LookiClient.journal(id:) async throws -> JournalPost`.
- `MomentCache`: `journals(for: DayKey) -> [JournalPost]?`, `storeJournals(_:for:)`,
  `journalDays() -> [DayKey]` (all cached days, for the feed), purge covers it.
- `MarkdownBlocks`: `enum MarkdownBlock { heading(level, text), paragraph(text), bullets([String]), image(alt, URL), rule }` and `static func parse(_ markdown: String) -> [MarkdownBlock]`.
- `JournalRenderer.render(day:moments:journals:generatedAt:)` — new optional `journals`
  parameter appends the `## Journal Looki` section; existing golden output unchanged when
  `journals` is empty.
- `DayArchiver.archive(day:moments:journals:into:)` — downloads journal media into
  `journal/`, writes `journals.json`; `fetchJournalDetail` injected like `fetchDetail`.
  New events reuse `.downloaded/.skipped` with the journal file name.

### 4.2 App additions
- `SidebarMode { moments, journal }` on `AppModel` (`var sidebarMode`), persisted in
  UserDefaults.
- `AppModel`: `journalDays: [JournalDay]` (merged cache + network, newest first),
  `journalState: idle/loading/loaded/failed`, `selectedPost: JournalPost?`,
  `showSystemPosts: Bool` (UserDefaults), `func loadJournal()` (cache → network, follows
  `has_more` up to 20 pages, stops on repeated first page), `func freshJournal(id:)`,
  `visibleJournalDays` (filtered by `showSystemPosts`).
- Views: `SidebarModePicker` (in `CalendarSidebarView` header), `JournalFeedView`
  (List with a `Section` per day, `ScrollViewReader` scroll-to-day on `selectedDay`
  change), `JournalCardView` (type badge, time, title/caption, thumbnail via
  `ThumbnailLoader` — extended with `image(for post:)` using the media thumbnail or
  source), `JournalPostDetailView` (media: image / `VideoPlayer` with fresh URL; title;
  description; `MarkdownBlocksView(content)`), `MarkdownBlocksView`.
- `RootView`: content column switches on `sidebarMode` (search mode still wins), detail
  column shows `JournalPostDetailView` when `selectedPost != nil` in journal mode. Toolbar
  "Archiver ce jour" stays enabled in journal mode (archives moments + journals of
  `selectedDay`).
- Settings: toggle « Afficher les annonces Looki ».

## 5. Error handling

| Situation | Behaviour |
|---|---|
| `/journals` fails | Feed shows cached days if any + banner; else failed state with retry |
| Unknown post type | Badge with raw type, rendered as text/media generically |
| Post without media | Text card, detail shows title + texts only |
| Expired media URL | Re-fetch `GET /journals/{id}` once (same as moments) |
| Cursor param ignored by API | Loader detects identical first item and stops; no infinite loop |
| Markdown with unsupported syntax | Rendered as paragraphs; images with invalid URL show alt text |

## 6. Testing

- Fixture `journals.json`: synthetic, two days, all six types + one `FUTURE_TYPE`.
- Decoding tests (types, optional fields, thumbnail, unknown type).
- `MarkdownBlocks.parse` tests on a sample recap and a sample system post (headings,
  bullets, images, rule, paragraphs, blank-line handling).
- `JournalRenderer` golden extended with journals section; existing golden still passes with
  `journals: []`.
- `DayArchiver` test: journal media lands in `journal/`, `journals.json` written,
  `SYSTEM_POST` skipped, thumbnails not downloaded.
- `LookiClient.journals` request/decoding via the URLProtocol stub, incl. cursor param.
- App: build with 0 warnings; manual smoke test.

## 7. Delivery

Branch `feat/journal`; merged into `main` after Vincent's smoke test; ships as **0.2.0**
(also carries the AVKit crash fix). CHANGELOG, README features table, landing page feature
card ("Journal") and hub manifest description updated in the same release.
