# Changelog

All notable changes to Looki pour Mac are documented here. Format based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow SemVer.

## [Unreleased]

## [0.2.0] — 2026-09-05

### Added
- **Journal**: the Looki feed of AI-generated posts (diary captions with image, comic page, daily vlog, health report, yesterday's recap) as a `Moments | Journal` sidebar mode — day-grouped feed, post detail with native Markdown rendering, Looki announcements hidden by default (Settings toggle).
- "Archiver ce jour" also saves the day's journal media into `journal/`, writes `journals.json`, and appends a `## Journal Looki` section to `journal.md`.
- `LookiKit`: `JournalPost` models, `journals` endpoints, per-day journal cache, `MarkdownBlocks` parser. 53 unit tests.

### Fixed
- Crash when opening a video moment (`failed to demangle superclass of VideoPlayerView`): with Xcode 27 the `import AVKit` autolink only pulls the `_AVKit_SwiftUI` overlay, so `AVKit.framework` is now linked explicitly. Affects 0.1.0 and 0.1.1.

## [0.1.1] — 2026-09-05

### Added
- App icon (rose-coral tile, camera glyph), generated from `Scripts/make-icon.swift`.

## [0.1.0] — 2026-09-05

First public release.

### Added
- Month calendar with marked days, day timeline with thumbnails extracted from each clip.
- Moment detail: native video/photo playback, AI description, address, duration.
- Semantic search across all moments, paginated.
- "Archive this day": one media file per moment, `journal.md` and `moments.json` in `YYYY/MM/DD/` under a folder you choose.
- Settings: API key in the Keychain, connection test, archive folder, cache purge, import from `~/.config/looki/credentials.json`.
- `LookiKit` Swift package (API client, models, cache, Markdown journal, archiver) with 39 unit tests.
- Signed and notarized DMG via `Scripts/release.sh`; trilingual landing page on GitHub Pages.

### Known limitations
- The Looki Open API exposes one cover media per moment and is read-only; the app cannot trigger captures or change device settings.
- No app icon yet; no auto-update.

[Unreleased]: https://github.com/vincentlauriat/LookiMac/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/vincentlauriat/LookiMac/releases/tag/v0.2.0
[0.1.1]: https://github.com/vincentlauriat/LookiMac/releases/tag/v0.1.1
[0.1.0]: https://github.com/vincentlauriat/LookiMac/releases/tag/v0.1.0
