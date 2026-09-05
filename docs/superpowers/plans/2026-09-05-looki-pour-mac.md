# Looki pour Mac Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS 26 app that browses, searches and archives the moments of a Looki L1 camera through the read-only Looki Open API.

**Architecture:** A local Swift package `LookiKit` (API client, models, cache, Markdown journal, day archiver) with no UI dependency and a full `swift test` suite. A thin SwiftUI app target `LookiMac` (xcodegen) owns the Keychain, the window (calendar → timeline → detail), search mode, settings and the archive command. Release via a Developer-ID-signed, notarized DMG.

**Tech Stack:** Swift 6 (strict concurrency), Swift Testing, SwiftUI, AVKit, Security (Keychain), URLSession, SwiftPM local package, xcodegen, Xcode 27, `Scripts/release.sh` (notarytool profile `AppliMacVincentGithub`).

**Spec:** `docs/superpowers/specs/2026-09-05-looki-pour-mac-design.md`

## Global Constraints

- Platform: **macOS 26 only** (`LSMinimumSystemVersion 26.0`, package platform `.macOS("26.0")`).
- Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete`. Every public LookiKit type is `Sendable`.
- App name **"Looki pour Mac"**, product name `LookiMac`, bundle id **`fr.lauriat.lookimac`**.
- API base URL `https://open.looki.ai/api/v1`; auth header **`x-api-key`**; envelope `{code, detail, data}`, `code == 0` = success.
- API key **only** in the login Keychain (service `fr.lauriat.lookimac`, account `api-key`). Never in UserDefaults, plist, source or fixtures.
- Signed video URLs (`temporary_url`) are **never written to the cache**; re-fetch `GET /moments/{id}` at playback/archive time.
- Cache root: `~/Library/Caches/fr.lauriat.lookimac/` (sandboxed container path is fine).
- UI strings in **French**; code, comments, commits and docs in **English**. Conventional commits, short, present tense, **no Co-Authored-By trailer**.
- Build check after every code change: `swift test` inside `LookiKit/` for the package; `xcodegen generate && xcodebuild -project LookiMac.xcodeproj -scheme LookiMac -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build` for the app. Prefix shell commands with `rtk` (hook does it automatically).
- Never commit `journal/`, `build/`, `release/`, `*.xcodeproj` (all gitignored). Work on a feature branch `feat/v1`; never push to `main`.
- Real personal data must not enter fixtures: fixtures below are synthetic but structurally identical to real responses captured 2026-09-05.

---

## File Structure

```
lookicheck/
├── project.yml                         xcodegen: app target LookiMac + local package LookiKit
├── LookiKit/                           SwiftPM package (no UI)
│   ├── Package.swift
│   ├── Sources/LookiKit/
│   │   ├── DayKey.swift                YYYY-MM-DD value type, Comparable, Codable
│   │   ├── Models.swift                Envelope, UserProfile, Moment, MomentFile, RemoteFile, FileMetadata, Location, MediaType, SearchPage
│   │   ├── LookiJSON.swift             JSONDecoder/JSONEncoder factories (dates with 6 fractional digits + offset)
│   │   ├── LookiError.swift            typed errors
│   │   ├── LookiClient.swift           actor: me / moments(on:) / moment(id:) / search; 429 retry
│   │   ├── MomentCache.swift           actor: per-day JSON + thumbnails, strips signed URLs
│   │   ├── JournalRenderer.swift       [Moment] -> Markdown
│   │   └── DayArchiver.swift           downloads cover media + journal.md + moments.json, AsyncThrowingStream progress
│   └── Tests/LookiKitTests/
│       ├── Fixtures/*.json             synthetic API responses (resources)
│       ├── Support/StubURLProtocol.swift
│       ├── Support/Fixture.swift       load(_ name:) -> Data
│       ├── DayKeyTests.swift
│       ├── ModelsTests.swift
│       ├── LookiClientTests.swift
│       ├── MomentCacheTests.swift
│       ├── JournalRendererTests.swift
│       └── DayArchiverTests.swift
├── LookiMac/                           SwiftUI app
│   ├── LookiMacApp.swift               @main, WindowGroup + Settings scene
│   ├── Info.plist, LookiMac.entitlements, Assets.xcassets
│   ├── Services/KeychainStore.swift    SecItem wrapper for the API key
│   ├── Services/ArchiveFolderBookmark.swift  security-scoped bookmark for the archive root
│   ├── Services/ThumbnailLoader.swift  cache-first thumbnails (AVAssetImageGenerator for video covers)
│   ├── Model/AppModel.swift            @MainActor @Observable root state
│   ├── Model/DayState.swift            enum idle/loading/loaded/empty/failed
│   ├── Model/Banner.swift              user-facing error banner model
│   └── Views/
│       ├── RootView.swift              NavigationSplitView + toolbar + banner
│       ├── CalendarSidebarView.swift   month grid with marks
│       ├── DayTimelineView.swift       list of MomentRowView for selected day
│       ├── MomentRowView.swift
│       ├── SearchResultsView.swift
│       ├── MomentDetailView.swift      VideoPlayer / image, description, address
│       ├── SettingsView.swift
│       └── EmptyStateView.swift
├── Scripts/release.sh
├── README.md
└── docs/superpowers/{specs,plans}/
```

---

### Task 1: LookiKit package scaffold with a first green test

**Files:**
- Create: `LookiKit/Package.swift`
- Create: `LookiKit/Sources/LookiKit/DayKey.swift`
- Create: `LookiKit/Tests/LookiKitTests/DayKeyTests.swift`

**Interfaces:**
- Produces: `public struct DayKey: Hashable, Sendable, Codable, Comparable, CustomStringConvertible` with `init(year:month:day:)`, `init?(string:)`, `init(date: Date, timeZone: TimeZone)`, `var string: String` (`"YYYY-MM-DD"`), `var year/month/day: Int`, `func date(in tz: TimeZone) -> Date` (midnight), `var pathComponents: [String]` (`["2026","09","05"]`).

- [ ] **Step 1: Create the branch and the package manifest**

```bash
git checkout -b feat/v1
mkdir -p LookiKit/Sources/LookiKit LookiKit/Tests/LookiKitTests/Fixtures LookiKit/Tests/LookiKitTests/Support
```

`LookiKit/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LookiKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "LookiKit", targets: ["LookiKit"]),
    ],
    targets: [
        .target(
            name: "LookiKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LookiKitTests",
            dependencies: ["LookiKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
```

- [ ] **Step 2: Write the failing test**

`LookiKit/Tests/LookiKitTests/DayKeyTests.swift`:

```swift
import Testing
import Foundation
@testable import LookiKit

@Suite struct DayKeyTests {
    @Test func parsesAndPrintsISODate() throws {
        let key = try #require(DayKey(string: "2026-09-05"))
        #expect(key.year == 2026)
        #expect(key.month == 9)
        #expect(key.day == 5)
        #expect(key.string == "2026-09-05")
        #expect(key.pathComponents == ["2026", "09", "05"])
    }

    @Test func rejectsGarbage() {
        #expect(DayKey(string: "yesterday") == nil)
        #expect(DayKey(string: "2026-13-01") == nil)
        #expect(DayKey(string: "2026-9-5") == nil)
    }

    @Test func comparesChronologically() {
        #expect(DayKey(year: 2026, month: 9, day: 4) < DayKey(year: 2026, month: 9, day: 5))
        #expect(DayKey(year: 2025, month: 12, day: 31) < DayKey(year: 2026, month: 1, day: 1))
    }

    @Test func buildsFromDateInTimeZone() {
        // 2026-09-04T23:30:00Z is already 2026-09-05 in Paris (+02:00).
        let utc = Date(timeIntervalSince1970: 1_788_564_600)
        let paris = TimeZone(secondsFromGMT: 7200)!
        #expect(DayKey(date: utc, timeZone: paris).string == "2026-09-05")
        #expect(DayKey(date: utc, timeZone: TimeZone(secondsFromGMT: 0)!).string == "2026-09-04")
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd LookiKit && swift test`
Expected: compile error, `DayKey` not found.

- [ ] **Step 4: Implement DayKey**

`LookiKit/Sources/LookiKit/DayKey.swift`:

```swift
import Foundation

/// A calendar day identified as `YYYY-MM-DD`, the unit the Looki API uses for `on_date`.
public struct DayKey: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Accepts strictly `YYYY-MM-DD` and validates the date against the Gregorian calendar.
    public init?(string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        guard cal.date(from: comps) != nil, (1...12).contains(m), (1...31).contains(d),
              cal.range(of: .day, in: .month, for: cal.date(from: comps)!)!.contains(d)
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public init(date: Date, timeZone: TimeZone) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    public var string: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var pathComponents: [String] {
        [String(format: "%04d", year), String(format: "%02d", month), String(format: "%02d", day)]
    }

    public var description: String { string }

    /// Midnight at the start of this day in `tz`.
    public func date(in tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // Codable as a plain "YYYY-MM-DD" string.
    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let k = DayKey(string: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid DayKey \(s)"))
        }
        self = k
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(string)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd LookiKit && swift test`
Expected: `Test run with 4 tests passed`.

- [ ] **Step 6: Commit**

```bash
git add LookiKit
git commit -m "feat(kit): scaffold LookiKit package with DayKey"
```

---

### Task 2: Models, JSON decoding and fixtures

**Files:**
- Create: `LookiKit/Sources/LookiKit/Models.swift`
- Create: `LookiKit/Sources/LookiKit/LookiJSON.swift`
- Create: `LookiKit/Tests/LookiKitTests/Support/Fixture.swift`
- Create: `LookiKit/Tests/LookiKitTests/Fixtures/me.json`, `moments-day.json`, `moment-detail.json`, `search.json`, `error-422.json`, `error-not-found.json`
- Create: `LookiKit/Tests/LookiKitTests/ModelsTests.swift`

**Interfaces:**
- Consumes: `DayKey` (Task 1).
- Produces:
  - `public struct Envelope<T: Decodable & Sendable>: Decodable, Sendable { code: Int; detail: String; data: T? }`
  - `public struct UserProfile: Codable, Sendable, Equatable { id, firstName?, lastName?, tz? }` and `public struct UserEnvelope: Decodable, Sendable { user: UserProfile }`
  - `public enum MediaType: String, Codable, Sendable { video = "VIDEO", image = "IMAGE", unknown }` (unknown raw values decode to `.unknown`)
  - `public struct FileMetadata: Codable, Sendable, Equatable { width?, height?, durationMs? }`
  - `public struct RemoteFile: Codable, Sendable, Equatable { temporaryURL: URL?; mediaType: MediaType; metadata: FileMetadata? }`
  - `public struct Location: Codable, Sendable, Equatable { street?, locality?, administrativeArea?, isoCountryCode?, subLocality? }` + `var shortLabel: String`
  - `public struct MomentFile: Codable, Sendable, Equatable { id: String; file: RemoteFile; location: Location?; createdAt: Date; tz: String }`
  - `public struct Moment: Codable, Sendable, Equatable, Hashable, Identifiable { id, title, description, mediaTypes: [MediaType], coverFile: MomentFile?, date: DayKey, tz: String, startTime: Date, endTime: Date }` + `var timeZone: TimeZone`, `func strippingSignedURLs() -> Moment`
  - `public struct SearchPage: Decodable, Sendable { items: [Moment]; hasMore: Bool }`
  - `public enum LookiJSON { static func decoder() -> JSONDecoder; static func encoder() -> JSONEncoder }`
  - `public extension TimeZone { static func fromOffset(_ s: String) -> TimeZone? }` (`"+02:00"` → 7200 s)

- [ ] **Step 1: Add the fixtures (synthetic, real structure)**

`Fixtures/me.json`:

```json
{"code":0,"detail":"OK","data":{"user":{"id":"11111111-2222-4333-8444-555555555555","first_name":"Test","last_name":null,"tz":"+02:00","gender":null,"birthday":null}}}
```

`Fixtures/moments-day.json`:

```json
{"code":0,"detail":"OK","data":[
 {"id":"aaaaaaaa-0000-4000-8000-000000000001","title":"Promenade au parc",
  "description":"L'utilisateur marche dans un parc ensoleillé, longe un étang et croise des joggeurs.",
  "media_types":["VIDEO"],
  "cover_file":{"id":"f00000000000000000000001",
    "file":{"temporary_url":"https://user-file.example.test/u/1.mp4?x-looki-token=SIGNED1","media_type":"VIDEO","metadata":{"height":1200,"duration_ms":5068,"width":1600}},
    "location":"{\"street\":\"Rue du Parc, 75000 Paris, France\",\"locality\":\"Paris\",\"administrativeArea\":\"Île-de-France\",\"isoCountryCode\":\"FR\"}",
    "created_at":"2026-09-05T10:02:03.568000+02:00","tz":"+02:00"},
  "date":"2026-09-05","tz":"+02:00","start_time":"2026-09-05T09:59:31.349000+02:00","end_time":"2026-09-05T10:03:22.192000+02:00"},
 {"id":"aaaaaaaa-0000-4000-8000-000000000002","title":"Déjeuner en terrasse",
  "description":"Repas partagé en terrasse, discussion animée autour d'un plat de pâtes.",
  "media_types":["IMAGE","VIDEO"],
  "cover_file":{"id":"f00000000000000000000002",
    "file":{"temporary_url":"https://user-file.example.test/u/2.jpg?x-looki-token=SIGNED2","media_type":"IMAGE","metadata":{"height":1200,"width":1600}},
    "location":"{\"street\":\"Place du Marché 3, 75000 Paris, France\",\"subLocality\":\"Centre\",\"locality\":\"Paris\",\"administrativeArea\":\"Île-de-France\",\"isoCountryCode\":\"FR\"}",
    "created_at":"2026-09-05T12:40:00.000000+02:00","tz":"+02:00"},
  "date":"2026-09-05","tz":"+02:00","start_time":"2026-09-05T12:35:52.228000+02:00","end_time":"2026-09-05T13:46:10.702000+02:00"}
]}
```

`Fixtures/moment-detail.json` — the first moment above, wrapped as a single object (same fields; the detail endpoint returns exactly the list entry):

```json
{"code":0,"detail":"OK","data":{"id":"aaaaaaaa-0000-4000-8000-000000000001","title":"Promenade au parc","description":"L'utilisateur marche dans un parc ensoleillé, longe un étang et croise des joggeurs.","media_types":["VIDEO"],"cover_file":{"id":"f00000000000000000000001","file":{"temporary_url":"https://user-file.example.test/u/1.mp4?x-looki-token=FRESH1","media_type":"VIDEO","metadata":{"height":1200,"duration_ms":5068,"width":1600}},"location":"{\"street\":\"Rue du Parc, 75000 Paris, France\",\"locality\":\"Paris\",\"administrativeArea\":\"Île-de-France\",\"isoCountryCode\":\"FR\"}","created_at":"2026-09-05T10:02:03.568000+02:00","tz":"+02:00"},"date":"2026-09-05","tz":"+02:00","start_time":"2026-09-05T09:59:31.349000+02:00","end_time":"2026-09-05T10:03:22.192000+02:00"}}
```

`Fixtures/search.json`:

```json
{"code":0,"detail":"OK","data":{"items":[{"id":"aaaaaaaa-0000-4000-8000-000000000002","title":"Déjeuner en terrasse","description":"Repas partagé en terrasse.","media_types":["IMAGE","VIDEO"],"cover_file":{"id":"f00000000000000000000002","file":{"temporary_url":"https://user-file.example.test/u/2.jpg?x-looki-token=SIGNED2","media_type":"IMAGE","metadata":{"height":1200,"width":1600}},"location":"{\"street\":\"Place du Marché 3, 75000 Paris, France\",\"locality\":\"Paris\",\"isoCountryCode\":\"FR\"}","created_at":"2026-09-05T12:40:00.000000+02:00","tz":"+02:00"},"date":"2026-09-05","tz":"+02:00","start_time":"2026-09-05T12:35:52.228000+02:00","end_time":"2026-09-05T13:46:10.702000+02:00"}],"has_more":true}}
```

`Fixtures/error-422.json`:

```json
{"code":100,"detail":"Invalid request parameters","data":{"errors":[{"type":"missing","loc":["header","x-api-key"],"msg":"Field required","input":"None"}]}}
```

`Fixtures/error-not-found.json`:

```json
{"code":101,"detail":"Moment with id aaaaaaaa-0000-4000-8000-00000000dead not found","data":null}
```

`Support/Fixture.swift`:

```swift
import Foundation

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}
```

(`#require` needs `import Testing` at top of the file; add it.)

- [ ] **Step 2: Write the failing tests**

`ModelsTests.swift`:

```swift
import Testing
import Foundation
@testable import LookiKit

@Suite struct ModelsTests {
    @Test func decodesMeEnvelope() throws {
        let env = try LookiJSON.decoder().decode(Envelope<UserEnvelope>.self, from: Fixture.data("me"))
        #expect(env.code == 0)
        let user = try #require(env.data?.user)
        #expect(user.id == "11111111-2222-4333-8444-555555555555")
        #expect(user.firstName == "Test")
        #expect(user.lastName == nil)
        #expect(user.tz == "+02:00")
    }

    @Test func decodesDayOfMoments() throws {
        let env = try LookiJSON.decoder().decode(Envelope<[Moment]>.self, from: Fixture.data("moments-day"))
        let moments = try #require(env.data)
        #expect(moments.count == 2)
        let first = moments[0]
        #expect(first.title == "Promenade au parc")
        #expect(first.mediaTypes == [.video])
        #expect(first.date == DayKey(year: 2026, month: 9, day: 5))
        #expect(first.timeZone.secondsFromGMT() == 7200)
        // 2026-09-05T09:59:31.349+02:00 == 07:59:31.349Z
        #expect(abs(first.startTime.timeIntervalSince1970 - 1_788_595_171.349) < 0.001)
        let cover = try #require(first.coverFile)
        #expect(cover.file.mediaType == .video)
        #expect(cover.file.metadata?.durationMs == 5068)
        #expect(cover.file.temporaryURL?.host() == "user-file.example.test")
        #expect(cover.location?.street == "Rue du Parc, 75000 Paris, France")
        #expect(cover.location?.locality == "Paris")
        #expect(moments[1].mediaTypes == [.image, .video])
        #expect(moments[1].coverFile?.location?.subLocality == "Centre")
    }

    @Test func unknownMediaTypeDoesNotFail() throws {
        let json = #"{"temporary_url":null,"media_type":"HOLOGRAM"}"#.data(using: .utf8)!
        let f = try LookiJSON.decoder().decode(RemoteFile.self, from: json)
        #expect(f.mediaType == .unknown)
        #expect(f.temporaryURL == nil)
    }

    @Test func emptyOrInvalidLocationStringBecomesNil() throws {
        let json = #"{"id":"x","file":{"temporary_url":null,"media_type":"IMAGE"},"location":"not json","created_at":"2026-09-05T10:02:03.568000+02:00","tz":"+02:00"}"#.data(using: .utf8)!
        let f = try LookiJSON.decoder().decode(MomentFile.self, from: json)
        #expect(f.location == nil)
    }

    @Test func decodesSearchPage() throws {
        let env = try LookiJSON.decoder().decode(Envelope<SearchPage>.self, from: Fixture.data("search"))
        let page = try #require(env.data)
        #expect(page.items.count == 1)
        #expect(page.hasMore == true)
    }

    @Test func decodesErrorEnvelopesWithAnyData() throws {
        let e1 = try LookiJSON.decoder().decode(Envelope<[Moment]>.self, from: Fixture.data("error-not-found"))
        #expect(e1.code == 101)
        #expect(e1.data == nil)
        // data is an unrelated object here: Envelope must still decode `code`/`detail`.
        let e2 = try LookiJSON.decoder().decode(Envelope<[Moment]>.self, from: Fixture.data("error-422"))
        #expect(e2.code == 100)
        #expect(e2.data == nil)
    }

    @Test func roundTripsThroughEncoderAndStripsSignedURLs() throws {
        let moments = try #require(try LookiJSON.decoder().decode(Envelope<[Moment]>.self, from: Fixture.data("moments-day")).data)
        let stripped = moments[0].strippingSignedURLs()
        #expect(stripped.coverFile?.file.temporaryURL == nil)
        #expect(stripped.coverFile?.id == moments[0].coverFile?.id)
        let data = try LookiJSON.encoder().encode(stripped)
        let back = try LookiJSON.decoder().decode(Moment.self, from: data)
        #expect(back == stripped)
    }

    @Test func locationShortLabel() {
        let l = Location(street: "Rue du Parc, 75000 Paris, France", locality: "Paris", administrativeArea: nil, isoCountryCode: "FR", subLocality: nil)
        #expect(l.shortLabel == "Rue du Parc, 75000 Paris, France")
        let onlyCity = Location(street: nil, locality: "Berlin", administrativeArea: nil, isoCountryCode: "DE", subLocality: nil)
        #expect(onlyCity.shortLabel == "Berlin")
    }

    @Test func timeZoneFromOffset() {
        #expect(TimeZone.fromOffset("+02:00")?.secondsFromGMT() == 7200)
        #expect(TimeZone.fromOffset("-05:30")?.secondsFromGMT() == -19800)
        #expect(TimeZone.fromOffset("Z")?.secondsFromGMT() == 0)
        #expect(TimeZone.fromOffset("bogus") == nil)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd LookiKit && swift test`
Expected: compile errors (`Envelope`, `Moment`, `LookiJSON` undefined).

- [ ] **Step 4: Implement LookiJSON**

`LookiJSON.swift`:

```swift
import Foundation

/// JSON coding configured for the Looki API: snake_case keys and ISO-8601 dates with
/// six fractional digits and a numeric offset (`2026-09-05T10:02:03.568000+02:00`).
public enum LookiJSON {
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unparseable date \(s)"))
        }
        return d
    }

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(formatDate(date))
        }
        return e
    }

    nonisolated(unsafe) private static let fractional: DateFormatter = make("yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX")
    nonisolated(unsafe) private static let fractional3: DateFormatter = make("yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX")
    nonisolated(unsafe) private static let plain: DateFormatter = make("yyyy-MM-dd'T'HH:mm:ssXXXXX")
    private static let lock = NSLock()

    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = format
        return f
    }

    static func parseDate(_ s: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return fractional.date(from: s) ?? fractional3.date(from: s) ?? plain.date(from: s)
    }

    static func formatDate(_ d: Date) -> String {
        lock.lock(); defer { lock.unlock() }
        return fractional.string(from: d)
    }
}

public extension TimeZone {
    /// Parses `"+02:00"`, `"-05:30"` or `"Z"`.
    static func fromOffset(_ s: String) -> TimeZone? {
        if s == "Z" { return TimeZone(secondsFromGMT: 0) }
        let sign: Int
        switch s.first {
        case "+": sign = 1
        case "-": sign = -1
        default: return nil
        }
        let body = s.dropFirst().split(separator: ":")
        guard body.count == 2, let h = Int(body[0]), let m = Int(body[1]), (0...14).contains(h), (0..<60).contains(m) else { return nil }
        return TimeZone(secondsFromGMT: sign * (h * 3600 + m * 60))
    }
}
```

Note: `DateFormatter` is not `Sendable`; the `NSLock` makes the shared instances safe. `nonisolated(unsafe)` is the Swift 6 way to declare that.

- [ ] **Step 5: Implement the models**

`Models.swift`:

```swift
import Foundation

/// Generic response envelope of the Looki Open API. `code == 0` means success.
/// `data` is decoded leniently: if it is absent, `null`, or not of type `T`
/// (error payloads put an `errors` object there), it becomes `nil`.
public struct Envelope<T: Decodable & Sendable>: Decodable, Sendable {
    public let code: Int
    public let detail: String
    public let data: T?

    public init(code: Int, detail: String, data: T?) {
        self.code = code; self.detail = detail; self.data = data
    }

    private enum CodingKeys: String, CodingKey { case code, detail, data }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(Int.self, forKey: .code)
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        if code == 0 {
            data = try c.decodeIfPresent(T.self, forKey: .data)
        } else {
            data = try? c.decodeIfPresent(T.self, forKey: .data)
        }
    }
}

public struct UserProfile: Codable, Sendable, Equatable {
    public let id: String
    public let firstName: String?
    public let lastName: String?
    public let tz: String?

    public var displayName: String {
        [firstName, lastName].compactMap { $0 }.joined(separator: " ")
    }
}

public struct UserEnvelope: Decodable, Sendable {
    public let user: UserProfile
}

public enum MediaType: String, Codable, Sendable, Hashable {
    case video = "VIDEO"
    case image = "IMAGE"
    case unknown = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MediaType(rawValue: raw) ?? .unknown
    }

    /// File extension used when archiving.
    public var fileExtension: String {
        switch self {
        case .video: "mp4"
        case .image: "jpg"
        case .unknown: "bin"
        }
    }
}

public struct FileMetadata: Codable, Sendable, Equatable, Hashable {
    public let width: Int?
    public let height: Int?
    public let durationMs: Int?
}

public struct RemoteFile: Codable, Sendable, Equatable, Hashable {
    /// Signed, expiring URL. `nil` once cached (see `Moment.strippingSignedURLs`).
    public var temporaryURL: URL?
    public let mediaType: MediaType
    public let metadata: FileMetadata?

    private enum CodingKeys: String, CodingKey { case temporaryURL = "temporaryUrl", mediaType, metadata }

    public init(temporaryURL: URL?, mediaType: MediaType, metadata: FileMetadata?) {
        self.temporaryURL = temporaryURL; self.mediaType = mediaType; self.metadata = metadata
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Signed URLs contain characters URL(string:) may reject; be lenient.
        if let s = try c.decodeIfPresent(String.self, forKey: .temporaryURL), !s.isEmpty {
            temporaryURL = URL(string: s)
        } else {
            temporaryURL = nil
        }
        mediaType = try c.decodeIfPresent(MediaType.self, forKey: .mediaType) ?? .unknown
        metadata = try c.decodeIfPresent(FileMetadata.self, forKey: .metadata)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(temporaryURL?.absoluteString, forKey: .temporaryURL)
        try c.encode(mediaType, forKey: .mediaType)
        try c.encodeIfPresent(metadata, forKey: .metadata)
    }
}

/// Reverse-geocoded place. The API ships it as a JSON **string** inside the file object.
public struct Location: Codable, Sendable, Equatable, Hashable {
    public let street: String?
    public let locality: String?
    public let administrativeArea: String?
    public let isoCountryCode: String?
    public let subLocality: String?

    public init(street: String?, locality: String?, administrativeArea: String?, isoCountryCode: String?, subLocality: String?) {
        self.street = street; self.locality = locality; self.administrativeArea = administrativeArea
        self.isoCountryCode = isoCountryCode; self.subLocality = subLocality
    }

    /// Street if known, else locality, else country code, else empty.
    public var shortLabel: String {
        street ?? locality ?? isoCountryCode ?? ""
    }

    static func parse(_ s: String?) -> Location? {
        guard let s, let data = s.data(using: .utf8) else { return nil }
        // Keys inside the string are camelCase already; use a plain decoder.
        return try? JSONDecoder().decode(Location.self, from: data)
    }
}

public struct MomentFile: Codable, Sendable, Equatable, Hashable {
    public let id: String
    public var file: RemoteFile
    public let location: Location?
    public let createdAt: Date
    public let tz: String

    private enum CodingKeys: String, CodingKey { case id, file, location, createdAt, tz }

    public init(id: String, file: RemoteFile, location: Location?, createdAt: Date, tz: String) {
        self.id = id; self.file = file; self.location = location; self.createdAt = createdAt; self.tz = tz
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        file = try c.decode(RemoteFile.self, forKey: .file)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        tz = try c.decodeIfPresent(String.self, forKey: .tz) ?? "+00:00"
        // Accept both the API form (string) and our own re-encoded form (object).
        if let obj = try? c.decodeIfPresent(Location.self, forKey: .location) {
            location = obj
        } else {
            location = Location.parse(try? c.decodeIfPresent(String.self, forKey: .location))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(file, forKey: .file)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(tz, forKey: .tz)
    }
}

public struct Moment: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let description: String
    public let mediaTypes: [MediaType]
    public var coverFile: MomentFile?
    public let date: DayKey
    public let tz: String
    public let startTime: Date
    public let endTime: Date

    public init(id: String, title: String, description: String, mediaTypes: [MediaType], coverFile: MomentFile?, date: DayKey, tz: String, startTime: Date, endTime: Date) {
        self.id = id; self.title = title; self.description = description; self.mediaTypes = mediaTypes
        self.coverFile = coverFile; self.date = date; self.tz = tz; self.startTime = startTime; self.endTime = endTime
    }

    /// The moment's own offset (e.g. `+02:00`), falling back to UTC.
    public var timeZone: TimeZone { TimeZone.fromOffset(tz) ?? TimeZone(secondsFromGMT: 0)! }

    public var duration: TimeInterval { endTime.timeIntervalSince(startTime) }

    /// Copy without any signed URL — the only form that may be written to disk caches.
    public func strippingSignedURLs() -> Moment {
        var copy = self
        copy.coverFile?.file.temporaryURL = nil
        return copy
    }
}

public struct SearchPage: Decodable, Sendable {
    public let items: [Moment]
    public let hasMore: Bool
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd LookiKit && swift test`
Expected: all `ModelsTests` and `DayKeyTests` pass. If `Bundle.module` is not found, check that `resources: [.copy("Fixtures")]` is in `Package.swift` and that the `Fixtures` folder sits directly under `Tests/LookiKitTests/`.

- [ ] **Step 7: Commit**

```bash
git add LookiKit
git commit -m "feat(kit): add API models, lenient envelope and JSON coding"
```

---

### Task 3: LookiClient with typed errors and a URLProtocol stub

**Files:**
- Create: `LookiKit/Sources/LookiKit/LookiError.swift`
- Create: `LookiKit/Sources/LookiKit/LookiClient.swift`
- Create: `LookiKit/Tests/LookiKitTests/Support/StubURLProtocol.swift`
- Create: `LookiKit/Tests/LookiKitTests/LookiClientTests.swift`

**Interfaces:**
- Consumes: `Envelope`, `UserEnvelope`, `Moment`, `SearchPage`, `DayKey`, `LookiJSON`.
- Produces:
  - `public enum LookiError: Error, Equatable, Sendable { missingAPIKey, unauthorized, rateLimited(retryAfter: TimeInterval?), httpStatus(Int), api(code: Int, detail: String), decoding(String), network(String) }` + `var userMessage: String` (French).
  - `public actor LookiClient` with `public static let defaultBaseURL: URL`, `init(apiKey: String, baseURL: URL = LookiClient.defaultBaseURL, session: URLSession = .shared, retryOnRateLimit: Bool = true)`, `func me() async throws -> UserProfile`, `func moments(on day: DayKey) async throws -> [Moment]`, `func moment(id: String) async throws -> Moment`, `func search(query: String, page: Int = 1, pageSize: Int = 20) async throws -> SearchPage`.

- [ ] **Step 1: Write the stub URLProtocol**

`Support/StubURLProtocol.swift`:

```swift
import Foundation

/// Records requests and replays canned responses, keyed by URL path.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response { let status: Int; let body: Data; let headers: [String: String] }

    nonisolated(unsafe) static var responses: [String: [Response]] = [:]   // path -> queue
    nonisolated(unsafe) static var requests: [URLRequest] = []
    static let lock = NSLock()

    static func reset() { lock.lock(); responses = [:]; requests = []; lock.unlock() }

    static func enqueue(path: String, status: Int = 200, body: Data, headers: [String: String] = [:]) {
        lock.lock(); responses[path, default: []].append(Response(status: status, body: body, headers: headers)); lock.unlock()
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let path = request.url!.path()
        let next = Self.responses[path]?.isEmpty == false ? Self.responses[path]!.removeFirst() : nil
        Self.lock.unlock()
        guard let next else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: "HTTP/1.1", headerFields: next.headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: next.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
```

- [ ] **Step 2: Write the failing tests**

`LookiClientTests.swift`:

```swift
import Testing
import Foundation
@testable import LookiKit

@Suite(.serialized) struct LookiClientTests {
    let base = URL(string: "https://open.looki.ai/api/v1")!

    func makeClient(retry: Bool = false) -> LookiClient {
        StubURLProtocol.reset()
        return LookiClient(apiKey: "lk-test", baseURL: base, session: StubURLProtocol.session(), retryOnRateLimit: retry)
    }

    @Test func meSendsHeaderAndDecodesUser() async throws {
        let client = makeClient()
        StubURLProtocol.enqueue(path: "/api/v1/me", body: try Fixture.data("me"))
        let user = try await client.me()
        #expect(user.firstName == "Test")
        let req = try #require(StubURLProtocol.requests.first)
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "lk-test")
        #expect(req.httpMethod == "GET")
    }

    @Test func momentsOnDayBuildsQuery() async throws {
        let client = makeClient()
        StubURLProtocol.enqueue(path: "/api/v1/moments", body: try Fixture.data("moments-day"))
        let moments = try await client.moments(on: DayKey(year: 2026, month: 9, day: 5))
        #expect(moments.count == 2)
        let url = try #require(StubURLProtocol.requests.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "on_date", value: "2026-09-05")))
        #expect(items.contains(URLQueryItem(name: "need_adjacent_date", value: "true")))
    }

    @Test func momentDetail() async throws {
        let client = makeClient()
        StubURLProtocol.enqueue(path: "/api/v1/moments/aaaaaaaa-0000-4000-8000-000000000001", body: try Fixture.data("moment-detail"))
        let m = try await client.moment(id: "aaaaaaaa-0000-4000-8000-000000000001")
        #expect(m.coverFile?.file.temporaryURL?.query()?.contains("FRESH1") == true)
    }

    @Test func searchPaginates() async throws {
        let client = makeClient()
        StubURLProtocol.enqueue(path: "/api/v1/moments/search", body: try Fixture.data("search"))
        let page = try await client.search(query: "déjeuner", page: 2, pageSize: 10)
        #expect(page.hasMore)
        let url = try #require(StubURLProtocol.requests.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "query", value: "déjeuner")))
        #expect(items.contains(URLQueryItem(name: "page", value: "2")))
        #expect(items.contains(URLQueryItem(name: "page_size", value: "10")))
    }

    @Test func missingKeyIsUnauthorized422() async throws {
        let client = makeClient()
        StubURLProtocol.enqueue(path: "/api/v1/me", status: 422, body: try Fixture.data("error-422"))
        await #expect(throws: LookiError.unauthorized) { try await client.me() }
    }

    @Test func status401IsUnauthorized() async throws {
        let client = makeClient()
        StubURLProtocol.enqueue(path: "/api/v1/me", status: 401, body: Data("{}".utf8))
        await #expect(throws: LookiError.unauthorized) { try await client.me() }
    }

    @Test func nonZeroCodeIsApiError() async throws {
        let client = makeClient()
        StubURLProtocol.enqueue(path: "/api/v1/moments/dead", body: try Fixture.data("error-not-found"))
        await #expect(throws: LookiError.api(code: 101, detail: "Moment with id aaaaaaaa-0000-4000-8000-00000000dead not found")) {
            try await client.moment(id: "dead")
        }
    }

    @Test func rateLimitWithoutRetryThrowsWithDelay() async throws {
        let client = makeClient(retry: false)
        StubURLProtocol.enqueue(path: "/api/v1/me", status: 429, body: Data(), headers: ["Retry-After": "7"])
        await #expect(throws: LookiError.rateLimited(retryAfter: 7)) { try await client.me() }
    }

    @Test func rateLimitWithRetrySucceedsOnSecondAttempt() async throws {
        let client = makeClient(retry: true)
        StubURLProtocol.enqueue(path: "/api/v1/me", status: 429, body: Data(), headers: ["Retry-After": "0"])
        StubURLProtocol.enqueue(path: "/api/v1/me", body: try Fixture.data("me"))
        let user = try await client.me()
        #expect(user.firstName == "Test")
        #expect(StubURLProtocol.requests.count == 2)
    }

    @Test func emptyKeyFailsBeforeNetwork() async throws {
        StubURLProtocol.reset()
        let client = LookiClient(apiKey: "   ", baseURL: base, session: StubURLProtocol.session())
        await #expect(throws: LookiError.missingAPIKey) { try await client.me() }
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test func garbageBodyIsDecodingError() async throws {
        let client = makeClient()
        StubURLProtocol.enqueue(path: "/api/v1/me", body: Data("<html>".utf8))
        do { _ = try await client.me(); Issue.record("expected throw") }
        catch let e as LookiError { if case .decoding = e {} else { Issue.record("wrong error \(e)") } }
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd LookiKit && swift test --filter LookiClientTests`
Expected: compile errors, `LookiClient`/`LookiError` undefined.

- [ ] **Step 4: Implement LookiError**

`LookiError.swift`:

```swift
import Foundation

public enum LookiError: Error, Equatable, Sendable {
    case missingAPIKey
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case httpStatus(Int)
    case api(code: Int, detail: String)
    case decoding(String)
    case network(String)

    /// Short French sentence suitable for a banner.
    public var userMessage: String {
        switch self {
        case .missingAPIKey: "Aucune clé API configurée."
        case .unauthorized: "Clé API refusée par Looki."
        case .rateLimited(let s):
            if let s { "Trop de requêtes. Nouvel essai dans \(Int(s.rounded())) s." } else { "Trop de requêtes. Réessaie dans un instant." }
        case .httpStatus(let code): "Le serveur Looki a répondu \(code)."
        case .api(_, let detail): "Looki : \(detail)"
        case .decoding: "Réponse inattendue du serveur Looki."
        case .network(let msg): "Réseau indisponible : \(msg)"
        }
    }
}
```

- [ ] **Step 5: Implement LookiClient**

`LookiClient.swift`:

```swift
import Foundation

/// Read-only client for the Looki Open API.
public actor LookiClient {
    public static let defaultBaseURL = URL(string: "https://open.looki.ai/api/v1")!

    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession
    private let retryOnRateLimit: Bool
    private let decoder = LookiJSON.decoder()

    public init(apiKey: String, baseURL: URL = LookiClient.defaultBaseURL, session: URLSession = .shared, retryOnRateLimit: Bool = true) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL
        self.session = session
        self.retryOnRateLimit = retryOnRateLimit
    }

    // MARK: Endpoints

    public func me() async throws -> UserProfile {
        try await get("me", as: UserEnvelope.self).user
    }

    public func moments(on day: DayKey) async throws -> [Moment] {
        try await get("moments", query: [
            URLQueryItem(name: "on_date", value: day.string),
            URLQueryItem(name: "need_adjacent_date", value: "true"),
        ], as: [Moment].self)
    }

    public func moment(id: String) async throws -> Moment {
        try await get("moments/\(id)", as: Moment.self)
    }

    public func search(query: String, page: Int = 1, pageSize: Int = 20) async throws -> SearchPage {
        try await get("moments/search", query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(pageSize)),
        ], as: SearchPage.self)
    }

    // MARK: Transport

    private func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        guard !apiKey.isEmpty else { throw LookiError.missingAPIKey }
        var comps = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var attempt = 0
        while true {
            attempt += 1
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw LookiError.network(error.localizedDescription)
            }
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0

            switch status {
            case 200..<300:
                return try decodeEnvelope(data, as: type)
            case 401, 403, 422:
                throw LookiError.unauthorized
            case 429:
                let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                if retryOnRateLimit, attempt == 1 {
                    let delay = min(retryAfter ?? 5, 30)
                    try await Task.sleep(for: .seconds(delay))
                    continue
                }
                throw LookiError.rateLimited(retryAfter: retryAfter)
            default:
                throw LookiError.httpStatus(status)
            }
        }
    }

    private func decodeEnvelope<T: Decodable & Sendable>(_ data: Data, as type: T.Type) throws -> T {
        let envelope: Envelope<T>
        do {
            envelope = try decoder.decode(Envelope<T>.self, from: data)
        } catch {
            throw LookiError.decoding(String(describing: error))
        }
        guard envelope.code == 0 else { throw LookiError.api(code: envelope.code, detail: envelope.detail) }
        guard let payload = envelope.data else { throw LookiError.decoding("Missing data for code 0") }
        return payload
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd LookiKit && swift test`
Expected: all suites green (DayKey 4, Models 9, Client 11).

- [ ] **Step 7: Commit**

```bash
git add LookiKit
git commit -m "feat(kit): add LookiClient with typed errors and 429 retry"
```

---

### Task 4: JournalRenderer (Markdown day journal)

**Files:**
- Create: `LookiKit/Sources/LookiKit/JournalRenderer.swift`
- Create: `LookiKit/Tests/LookiKitTests/JournalRendererTests.swift`

**Interfaces:**
- Consumes: `Moment`, `DayKey`, `TimeZone.fromOffset`.
- Produces: `public enum JournalRenderer { public static func render(day: DayKey, moments: [Moment], generatedAt: Date, locale: Locale = Locale(identifier: "fr_FR")) -> String }`. Output layout is identical to the prototype `journal/2026-09-05.md`: title, summary quote, chronology table, narrative sections, footer with the API request and moment ids.

- [ ] **Step 1: Write the failing golden test**

```swift
import Testing
import Foundation
@testable import LookiKit

@Suite struct JournalRendererTests {
    @Test func rendersGoldenJournal() throws {
        let moments = try #require(try LookiJSON.decoder().decode(Envelope<[Moment]>.self, from: Fixture.data("moments-day")).data)
        let generated = try #require(LookiJSON.parseDate("2026-09-05T18:30:00.000000+02:00"))
        let md = JournalRenderer.render(day: DayKey(year: 2026, month: 9, day: 5), moments: moments, generatedAt: generated)

        let expected = """
        # Journal Looki — samedi 5 septembre 2026

        > 2 moments · 09:59 → 13:46 · 1 h 14 enregistrées · Paris

        ## Chronologie

        | Heure | Moment | Lieu | Média |
        |---|---|---|---|
        | 09:59–10:03 | [Promenade au parc](#aaaaaaaa) | Rue du Parc, 75000 Paris, France | vidéo |
        | 12:35–13:46 | [Déjeuner en terrasse](#aaaaaaaa) | Place du Marché 3, 75000 Paris, France | photo, vidéo |

        ## Récit de la journée

        ### 09:59 · Promenade au parc <a id="aaaaaaaa"></a>

        *09:59–10:03 (3 min) · Rue du Parc, 75000 Paris, France*

        L'utilisateur marche dans un parc ensoleillé, longe un étang et croise des joggeurs.

        ### 12:35 · Déjeuner en terrasse <a id="aaaaaaaa"></a>

        *12:35–13:46 (1 h 10) · Place du Marché 3, 75000 Paris, France*

        Repas partagé en terrasse, discussion animée autour d'un plat de pâtes.

        ---

        *Généré depuis l'API Looki (`GET /moments?on_date=2026-09-05`) le 2026-09-05 18:30. Identifiants des moments : `aaaaaaaa-0000-4000-8000-000000000001`, `aaaaaaaa-0000-4000-8000-000000000002`.*

        """
        #expect(md == expected)
    }

    @Test func emptyDayStillRenders() {
        let md = JournalRenderer.render(day: DayKey(year: 2026, month: 9, day: 6), moments: [], generatedAt: Date(timeIntervalSince1970: 0))
        #expect(md.contains("# Journal Looki — dimanche 6 septembre 2026"))
        #expect(md.contains("> 0 moment · aucune capture ce jour"))
        #expect(!md.contains("## Chronologie"))
    }

    @Test func sortsByStartTime() throws {
        var moments = try #require(try LookiJSON.decoder().decode(Envelope<[Moment]>.self, from: Fixture.data("moments-day")).data)
        moments.reverse()
        let md = JournalRenderer.render(day: DayKey(year: 2026, month: 9, day: 5), moments: moments, generatedAt: Date(timeIntervalSince1970: 0))
        let parc = md.range(of: "### 09:59")!.lowerBound
        let dej = md.range(of: "### 12:35")!.lowerBound
        #expect(parc < dej)
    }
}
```

Note the anchors: both fixture ids share the prefix `aaaaaaaa`, so the anchors collide in this fixture — that is fine for the golden test and matches the renderer rule "first 8 characters of the id". (2026-09-05 is a Saturday; the French weekday comes from `Locale("fr_FR")`.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd LookiKit && swift test --filter JournalRendererTests`
Expected: compile error, `JournalRenderer` undefined.

- [ ] **Step 3: Implement the renderer**

```swift
import Foundation

/// Renders a day's moments as the Markdown journal format used by Looki pour Mac.
public enum JournalRenderer {
    public static func render(day: DayKey, moments input: [Moment], generatedAt: Date, locale: Locale = Locale(identifier: "fr_FR")) -> String {
        let moments = input.sorted { $0.startTime < $1.startTime }
        var out: [String] = []

        out.append("# Journal Looki — \(longDate(day, locale: locale))")
        out.append("")
        if moments.isEmpty {
            out.append("> 0 moment · aucune capture ce jour")
            out.append("")
        } else {
            let total = moments.reduce(0) { $0 + $1.duration }
            let cities = moments.compactMap { $0.coverFile?.location?.locality }.uniqued()
            let cityPart = cities.isEmpty ? "" : " · \(cities.joined(separator: ", "))"
            out.append("> \(moments.count) moments · \(hm(moments.first!)) → \(hmEnd(moments.last!)) · \(durationLong(total)) enregistrées\(cityPart)")
            out.append("")
            out.append("## Chronologie")
            out.append("")
            out.append("| Heure | Moment | Lieu | Média |")
            out.append("|---|---|---|---|")
            for m in moments {
                out.append("| \(range(m)) | [\(m.title)](#\(anchor(m))) | \(place(m)) | \(media(m)) |")
            }
            out.append("")
            out.append("## Récit de la journée")
            out.append("")
            for m in moments {
                out.append("### \(hm(m)) · \(m.title) <a id=\"\(anchor(m))\"></a>")
                out.append("")
                out.append("*\(range(m)) (\(durationShort(m.duration))) · \(place(m))*")
                out.append("")
                out.append(m.description.trimmingCharacters(in: .whitespacesAndNewlines))
                out.append("")
            }
        }
        out.append("---")
        out.append("")
        let ids = moments.map { "`\($0.id)`" }.joined(separator: ", ")
        let idsPart = moments.isEmpty ? "Aucun identifiant." : "Identifiants des moments : \(ids)."
        out.append("*Généré depuis l'API Looki (`GET /moments?on_date=\(day.string)`) le \(stamp(generatedAt, tz: moments.first?.timeZone ?? TimeZone(secondsFromGMT: 7200)!)). \(idsPart)*")
        out.append("")
        return out.joined(separator: "\n")
    }

    // MARK: Helpers

    private static func anchor(_ m: Moment) -> String { String(m.id.prefix(8)) }

    private static func place(_ m: Moment) -> String {
        let label = m.coverFile?.location?.shortLabel ?? ""
        return label.isEmpty ? "?" : label
    }

    private static func media(_ m: Moment) -> String {
        m.mediaTypes.map {
            switch $0 {
            case .video: "vidéo"
            case .image: "photo"
            case .unknown: "autre"
            }
        }.joined(separator: ", ")
    }

    private static func hm(_ m: Moment) -> String { time(m.startTime, tz: m.timeZone) }
    private static func hmEnd(_ m: Moment) -> String { time(m.endTime, tz: m.timeZone) }
    private static func range(_ m: Moment) -> String { "\(hm(m))–\(hmEnd(m))" }

    private static func time(_ d: Date, tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = tz; f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private static func stamp(_ d: Date, tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = tz; f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }

    private static func longDate(_ day: DayKey, locale: Locale) -> String {
        let f = DateFormatter()
        f.locale = locale; f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "EEEE d MMMM yyyy"
        return f.string(from: day.date(in: TimeZone(secondsFromGMT: 0)!))
    }

    /// "3 min" under an hour, "1 h 10" above.
    static func durationShort(_ seconds: TimeInterval) -> String {
        let mn = Int(seconds / 60)
        return mn >= 60 ? "\(mn / 60) h \(String(format: "%02d", mn % 60))" : "\(mn) min"
    }

    /// Always "H h MM" form for the day total.
    static func durationLong(_ seconds: TimeInterval) -> String {
        let mn = Int(seconds / 60)
        return "\(mn / 60) h \(String(format: "%02d", mn % 60))"
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LookiKit && swift test --filter JournalRendererTests`
Expected: 3 tests pass. If the golden differs only in the weekday/month words, check that `fr_FR` is used and the machine has the French locale data (it always does on macOS).

- [ ] **Step 5: Commit**

```bash
git add LookiKit
git commit -m "feat(kit): add Markdown JournalRenderer with golden test"
```

---

### Task 5: MomentCache (per-day JSON + thumbnails)

**Files:**
- Create: `LookiKit/Sources/LookiKit/MomentCache.swift`
- Create: `LookiKit/Tests/LookiKitTests/MomentCacheTests.swift`

**Interfaces:**
- Consumes: `Moment.strippingSignedURLs()`, `DayKey`, `LookiJSON`.
- Produces: `public actor MomentCache` with `init(root: URL)`, `static func defaultRoot() -> URL` (`~/Library/Caches/fr.lauriat.lookimac`), `func day(_ key: DayKey) -> DayRecord?`, `func store(_ moments: [Moment], for key: DayKey) throws`, `func fetchedDays(year: Int, month: Int) -> [DayKey: Int]` (day → moment count, for every fetched day of that month), `func thumbnail(for fileID: String) -> Data?`, `func storeThumbnail(_ data: Data, for fileID: String) throws`, `func purge() throws`, `func sizeOnDisk() -> Int64`.
- `public struct DayRecord: Codable, Sendable, Equatable { fetchedAt: Date; moments: [Moment] }`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import LookiKit

@Suite struct MomentCacheTests {
    func tempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "lookikit-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func fixtureMoments() throws -> [Moment] {
        try #require(try LookiJSON.decoder().decode(Envelope<[Moment]>.self, from: Fixture.data("moments-day")).data)
    }

    @Test func storesAndReadsBackADayWithoutSignedURLs() async throws {
        let cache = MomentCache(root: try tempRoot())
        let day = DayKey(year: 2026, month: 9, day: 5)
        try await cache.store(try fixtureMoments(), for: day)
        let record = try #require(await cache.day(day))
        #expect(record.moments.count == 2)
        #expect(record.moments.allSatisfy { $0.coverFile?.file.temporaryURL == nil })
        #expect(record.moments[0].title == "Promenade au parc")
    }

    @Test func diskFileNeverContainsToken() async throws {
        let root = try tempRoot()
        let cache = MomentCache(root: root)
        let day = DayKey(year: 2026, month: 9, day: 5)
        try await cache.store(try fixtureMoments(), for: day)
        let file = root.appending(path: "days/2026-09-05.json")
        let raw = try String(contentsOf: file, encoding: .utf8)
        #expect(!raw.contains("x-looki-token"))
        #expect(!raw.contains("SIGNED"))
    }

    @Test func missingDayIsNil() async throws {
        let cache = MomentCache(root: try tempRoot())
        #expect(await cache.day(DayKey(year: 2026, month: 1, day: 1)) == nil)
    }

    @Test func emptyDayIsRecordedAsFetched() async throws {
        let cache = MomentCache(root: try tempRoot())
        let day = DayKey(year: 2026, month: 9, day: 6)
        try await cache.store([], for: day)
        let record = try #require(await cache.day(day))
        #expect(record.moments.isEmpty)
        let month = await cache.fetchedDays(year: 2026, month: 9)
        #expect(month[day] == 0)
    }

    @Test func fetchedDaysListsOnlyThatMonth() async throws {
        let cache = MomentCache(root: try tempRoot())
        try await cache.store(try fixtureMoments(), for: DayKey(year: 2026, month: 9, day: 5))
        try await cache.store([], for: DayKey(year: 2026, month: 9, day: 6))
        try await cache.store(try fixtureMoments(), for: DayKey(year: 2026, month: 8, day: 31))
        let sept = await cache.fetchedDays(year: 2026, month: 9)
        #expect(sept.count == 2)
        #expect(sept[DayKey(year: 2026, month: 9, day: 5)] == 2)
        #expect(await cache.fetchedDays(year: 2026, month: 8).count == 1)
        #expect(await cache.fetchedDays(year: 2025, month: 9).isEmpty)
    }

    @Test func thumbnailsRoundTripAndPurgeClearsEverything() async throws {
        let root = try tempRoot()
        let cache = MomentCache(root: root)
        try await cache.storeThumbnail(Data([0xFF, 0xD8, 0xFF]), for: "f00000000000000000000001")
        #expect(await cache.thumbnail(for: "f00000000000000000000001") == Data([0xFF, 0xD8, 0xFF]))
        #expect(await cache.thumbnail(for: "nope") == nil)
        try await cache.store(try fixtureMoments(), for: DayKey(year: 2026, month: 9, day: 5))
        #expect(await cache.sizeOnDisk() > 0)
        try await cache.purge()
        #expect(await cache.thumbnail(for: "f00000000000000000000001") == nil)
        #expect(await cache.day(DayKey(year: 2026, month: 9, day: 5)) == nil)
        #expect(await cache.sizeOnDisk() == 0)
    }

    @Test func rejectsUnsafeFileIDs() async throws {
        let cache = MomentCache(root: try tempRoot())
        await #expect(throws: MomentCache.CacheError.invalidIdentifier) {
            try await cache.storeThumbnail(Data([1]), for: "../etc/passwd")
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LookiKit && swift test --filter MomentCacheTests`
Expected: compile error, `MomentCache` undefined.

- [ ] **Step 3: Implement the cache**

```swift
import Foundation

public struct DayRecord: Codable, Sendable, Equatable {
    public let fetchedAt: Date
    public let moments: [Moment]
}

/// Disk cache of moment metadata (one JSON per day) and thumbnails (one file per cover id).
/// Signed URLs are stripped before writing. Everything lives under `root` and can be purged.
public actor MomentCache {
    public enum CacheError: Error, Equatable { case invalidIdentifier }

    private let root: URL
    private let fm = FileManager.default
    private let encoder = LookiJSON.encoder()
    private let decoder = LookiJSON.decoder()

    public init(root: URL) { self.root = root }

    public static func defaultRoot() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appending(path: "fr.lauriat.lookimac")
    }

    private var daysDir: URL { root.appending(path: "days") }
    private var thumbsDir: URL { root.appending(path: "thumbs") }

    // MARK: Days

    public func day(_ key: DayKey) -> DayRecord? {
        guard let data = try? Data(contentsOf: daysDir.appending(path: "\(key.string).json")) else { return nil }
        return try? decoder.decode(DayRecord.self, from: data)
    }

    public func store(_ moments: [Moment], for key: DayKey) throws {
        try fm.createDirectory(at: daysDir, withIntermediateDirectories: true)
        let record = DayRecord(fetchedAt: Date(), moments: moments.map { $0.strippingSignedURLs() })
        try encoder.encode(record).write(to: daysDir.appending(path: "\(key.string).json"), options: .atomic)
    }

    /// Every fetched day of the month, with its moment count (0 for empty days).
    public func fetchedDays(year: Int, month: Int) -> [DayKey: Int] {
        let prefix = String(format: "%04d-%02d-", year, month)
        guard let names = try? fm.contentsOfDirectory(atPath: daysDir.path()) else { return [:] }
        var result: [DayKey: Int] = [:]
        for name in names where name.hasPrefix(prefix) && name.hasSuffix(".json") {
            guard let key = DayKey(string: String(name.dropLast(5))), let record = day(key) else { continue }
            result[key] = record.moments.count
        }
        return result
    }

    // MARK: Thumbnails

    public func thumbnail(for fileID: String) -> Data? {
        guard Self.isSafe(fileID) else { return nil }
        return try? Data(contentsOf: thumbsDir.appending(path: "\(fileID).jpg"))
    }

    public func storeThumbnail(_ data: Data, for fileID: String) throws {
        guard Self.isSafe(fileID) else { throw CacheError.invalidIdentifier }
        try fm.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
        try data.write(to: thumbsDir.appending(path: "\(fileID).jpg"), options: .atomic)
    }

    // MARK: Maintenance

    public func purge() throws {
        for dir in [daysDir, thumbsDir] where fm.fileExists(atPath: dir.path()) {
            try fm.removeItem(at: dir)
        }
    }

    public func sizeOnDisk() -> Int64 {
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    /// Identifiers become file names: only hex/alphanumerics, dashes and underscores allowed.
    static func isSafe(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LookiKit && swift test --filter MomentCacheTests`
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add LookiKit
git commit -m "feat(kit): add MomentCache for day metadata and thumbnails"
```

---

### Task 6: DayArchiver (media download + journal.md + moments.json)

**Files:**
- Create: `LookiKit/Sources/LookiKit/DayArchiver.swift`
- Create: `LookiKit/Tests/LookiKitTests/DayArchiverTests.swift`

**Interfaces:**
- Consumes: `Moment`, `DayKey`, `JournalRenderer.render`, `LookiJSON.encoder()`, `LookiClient.moment(id:)`.
- Produces:
  - `public protocol MediaDownloader: Sendable { func download(_ url: URL, to destination: URL) async throws }` and `public struct URLSessionDownloader: MediaDownloader` (`init(session: URLSession = .shared)`).
  - `public enum ArchiveEvent: Sendable, Equatable { started(total: Int), downloaded(momentID: String, fileName: String), skipped(momentID: String, reason: String), wroteJournal(URL), finished(folder: URL) }`
  - `public struct DayArchiver: Sendable` with `init(fetchDetail: @Sendable @escaping (String) async throws -> Moment, downloader: MediaDownloader)`, convenience `init(client: LookiClient, downloader: MediaDownloader = URLSessionDownloader())`, `func archive(day: DayKey, moments: [Moment], into root: URL) -> AsyncThrowingStream<ArchiveEvent, Error>`, `static func folder(for day: DayKey, in root: URL) -> URL` (`root/YYYY/MM/DD`), `static func fileName(for moment: Moment) -> String` (`HHmm-<id prefix 8>.<ext>` in the moment's own time zone).

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import LookiKit

@Suite struct DayArchiverTests {
    /// Writes a marker body so the test can verify which URL landed where.
    struct FakeDownloader: MediaDownloader {
        func download(_ url: URL, to destination: URL) async throws {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(url.absoluteString.utf8).write(to: destination)
        }
    }

    func tempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "lookikit-archive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func fixtureMoments() throws -> [Moment] {
        try #require(try LookiJSON.decoder().decode(Envelope<[Moment]>.self, from: Fixture.data("moments-day")).data)
    }

    func collect(_ stream: AsyncThrowingStream<ArchiveEvent, Error>) async throws -> [ArchiveEvent] {
        var events: [ArchiveEvent] = []
        for try await e in stream { events.append(e) }
        return events
    }

    @Test func folderAndFileNaming() throws {
        let m = try fixtureMoments()[0]
        let root = URL(filePath: "/tmp/archive")
        #expect(DayArchiver.folder(for: m.date, in: root).path() == "/tmp/archive/2026/09/05")
        #expect(DayArchiver.fileName(for: m) == "0959-aaaaaaaa.mp4")
        #expect(DayArchiver.fileName(for: try fixtureMoments()[1]) == "1235-aaaaaaaa.jpg")
    }

    @Test func archivesADayUsingFreshDetailURLs() async throws {
        let root = try tempRoot()
        let moments = try fixtureMoments()
        let fresh = try #require(try LookiJSON.decoder().decode(Envelope<Moment>.self, from: Fixture.data("moment-detail")).data)
        let archiver = DayArchiver(
            fetchDetail: { id in id == fresh.id ? fresh : moments[1] },
            downloader: FakeDownloader()
        )
        let events = try await collect(archiver.archive(day: moments[0].date, moments: moments, into: root))
        let folder = root.appending(path: "2026/09/05")

        #expect(events.first == .started(total: 2))
        #expect(events.contains(.downloaded(momentID: moments[0].id, fileName: "0959-aaaaaaaa.mp4")))
        #expect(events.contains(.downloaded(momentID: moments[1].id, fileName: "1235-aaaaaaaa.jpg")))
        #expect(events.last == .finished(folder: folder))

        // The video was fetched through the FRESH detail URL, not the stale list URL.
        let body = try String(contentsOf: folder.appending(path: "0959-aaaaaaaa.mp4"), encoding: .utf8)
        #expect(body.contains("FRESH1"))

        let journal = try String(contentsOf: folder.appending(path: "journal.md"), encoding: .utf8)
        #expect(journal.hasPrefix("# Journal Looki — samedi 5 septembre 2026"))

        let raw = try Data(contentsOf: folder.appending(path: "moments.json"))
        let back = try LookiJSON.decoder().decode([Moment].self, from: raw)
        #expect(back.count == 2)
        #expect(back.allSatisfy { $0.coverFile?.file.temporaryURL == nil })
    }

    @Test func skipsExistingNonEmptyFiles() async throws {
        let root = try tempRoot()
        let moments = try fixtureMoments()
        let folder = DayArchiver.folder(for: moments[0].date, in: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("already".utf8).write(to: folder.appending(path: "0959-aaaaaaaa.mp4"))
        var detailCalls = 0
        let counter = Counter()
        let archiver = DayArchiver(
            fetchDetail: { id in await counter.increment(); return moments.first { $0.id == id }! },
            downloader: FakeDownloader()
        )
        let events = try await collect(archiver.archive(day: moments[0].date, moments: moments, into: root))
        detailCalls = await counter.value
        #expect(detailCalls == 1)   // only the second moment needed a fresh URL
        #expect(events.contains(.skipped(momentID: moments[0].id, reason: "déjà archivé")))
        #expect(try String(contentsOf: folder.appending(path: "0959-aaaaaaaa.mp4"), encoding: .utf8) == "already")
    }

    @Test func momentWithoutCoverIsSkippedNotFatal() async throws {
        let root = try tempRoot()
        var moments = try fixtureMoments()
        moments[0].coverFile = nil
        let archiver = DayArchiver(fetchDetail: { id in moments.first { $0.id == id }! }, downloader: FakeDownloader())
        let events = try await collect(archiver.archive(day: moments[0].date, moments: moments, into: root))
        #expect(events.contains(.skipped(momentID: moments[0].id, reason: "aucun média")))
        #expect(events.contains(.downloaded(momentID: moments[1].id, fileName: "1235-aaaaaaaa.jpg")))
    }

    @Test func detailFailureIsReportedAsSkippedAndArchiveContinues() async throws {
        let root = try tempRoot()
        let moments = try fixtureMoments()
        let archiver = DayArchiver(
            fetchDetail: { id in
                if id == moments[0].id { throw LookiError.api(code: 101, detail: "not found") }
                return moments[1]
            },
            downloader: FakeDownloader()
        )
        let events = try await collect(archiver.archive(day: moments[0].date, moments: moments, into: root))
        #expect(events.contains(.skipped(momentID: moments[0].id, reason: "Looki : not found")))
        #expect(events.last == .finished(folder: root.appending(path: "2026/09/05")))
    }
}

actor Counter {
    var value = 0
    func increment() { value += 1 }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LookiKit && swift test --filter DayArchiverTests`
Expected: compile error, `DayArchiver` undefined.

- [ ] **Step 3: Implement the archiver**

```swift
import Foundation

public protocol MediaDownloader: Sendable {
    /// Downloads `url` to `destination`, creating parent folders. Must be atomic (temp file + move).
    func download(_ url: URL, to destination: URL) async throws
}

public struct URLSessionDownloader: MediaDownloader {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func download(_ url: URL, to destination: URL) async throws {
        let (tmp, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: tmp)
            throw LookiError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path()) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: tmp, to: destination)
    }
}

public enum ArchiveEvent: Sendable, Equatable {
    case started(total: Int)
    case downloaded(momentID: String, fileName: String)
    case skipped(momentID: String, reason: String)
    case wroteJournal(URL)
    case finished(folder: URL)
}

/// Archives one day: `<root>/YYYY/MM/DD/{HHmm-<id8>.<ext>, journal.md, moments.json}`.
/// Cover media is downloaded through a fresh `GET /moments/{id}` so signed URLs are valid.
public struct DayArchiver: Sendable {
    public typealias DetailFetcher = @Sendable (String) async throws -> Moment

    private let fetchDetail: DetailFetcher
    private let downloader: MediaDownloader

    public init(fetchDetail: @escaping DetailFetcher, downloader: MediaDownloader) {
        self.fetchDetail = fetchDetail
        self.downloader = downloader
    }

    public init(client: LookiClient, downloader: MediaDownloader = URLSessionDownloader()) {
        self.init(fetchDetail: { id in try await client.moment(id: id) }, downloader: downloader)
    }

    public static func folder(for day: DayKey, in root: URL) -> URL {
        day.pathComponents.reduce(root) { $0.appending(path: $1) }
    }

    public static func fileName(for moment: Moment) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = moment.timeZone; f.dateFormat = "HHmm"
        let ext = moment.coverFile?.file.mediaType.fileExtension ?? "bin"
        return "\(f.string(from: moment.startTime))-\(moment.id.prefix(8)).\(ext)"
    }

    public func archive(day: DayKey, moments input: [Moment], into root: URL) -> AsyncThrowingStream<ArchiveEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let fm = FileManager.default
                    let moments = input.sorted { $0.startTime < $1.startTime }
                    let folder = Self.folder(for: day, in: root)
                    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                    continuation.yield(.started(total: moments.count))

                    for m in moments {
                        try Task.checkCancellation()
                        guard m.coverFile != nil else {
                            continuation.yield(.skipped(momentID: m.id, reason: "aucun média")); continue
                        }
                        let name = Self.fileName(for: m)
                        let dest = folder.appending(path: name)
                        if let size = try? fm.attributesOfItem(atPath: dest.path())[.size] as? Int, size > 0 {
                            continuation.yield(.skipped(momentID: m.id, reason: "déjà archivé")); continue
                        }
                        do {
                            let fresh = try await fetchDetail(m.id)
                            guard let url = fresh.coverFile?.file.temporaryURL else {
                                continuation.yield(.skipped(momentID: m.id, reason: "URL absente")); continue
                            }
                            try await downloader.download(url, to: dest)
                            continuation.yield(.downloaded(momentID: m.id, fileName: name))
                        } catch let e as LookiError {
                            continuation.yield(.skipped(momentID: m.id, reason: e.userMessage))
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            continuation.yield(.skipped(momentID: m.id, reason: error.localizedDescription))
                        }
                    }

                    let journalURL = folder.appending(path: "journal.md")
                    let markdown = JournalRenderer.render(day: day, moments: moments, generatedAt: Date())
                    try markdown.write(to: journalURL, atomically: true, encoding: .utf8)
                    continuation.yield(.wroteJournal(journalURL))

                    let json = try LookiJSON.encoder().encode(moments.map { $0.strippingSignedURLs() })
                    try json.write(to: folder.appending(path: "moments.json"), options: .atomic)

                    continuation.yield(.finished(folder: folder))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

- [ ] **Step 4: Run the whole package suite**

Run: `cd LookiKit && swift test`
Expected: everything green (DayKey 4, Models 9, Client 11, Journal 3, Cache 7, Archiver 5 = 39 tests).

- [ ] **Step 5: Commit**

```bash
git add LookiKit
git commit -m "feat(kit): add DayArchiver with progress stream"
```

---

### Task 7: xcodegen project, app skeleton, Keychain store

**Files:**
- Create: `project.yml`
- Create: `LookiMac/LookiMacApp.swift`, `LookiMac/Info.plist`, `LookiMac/LookiMac.entitlements`, `LookiMac/Assets.xcassets/Contents.json`, `LookiMac/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `LookiMac/Services/KeychainStore.swift`
- Create: `LookiMac/Model/AppModel.swift` (first version: credentials only)
- Create: `LookiMac/Views/RootView.swift` (placeholder text, replaced in Task 9)
- Modify: `.gitignore` (already ignores `*.xcodeproj`, `build/`) — verify only.

**Interfaces:**
- Consumes: `LookiClient`, `MomentCache`.
- Produces:
  - `enum KeychainStore { static func readAPIKey() throws -> String?; static func saveAPIKey(_ key: String) throws; static func deleteAPIKey() throws }` (service `fr.lauriat.lookimac`, account `api-key`).
  - `@MainActor @Observable final class AppModel` with `var apiKey: String?` (read-only outside), `var client: LookiClient?`, `let cache: MomentCache`, `func setAPIKey(_ key: String) throws`, `func clearAPIKey() throws`, `var needsSetup: Bool`.

- [ ] **Step 1: Write project.yml**

```yaml
name: LookiMac
options:
  bundleIdPrefix: fr.lauriat
  deploymentTarget:
    macOS: "26.0"
  xcodeVersion: "27.0"
  generateEmptyDirectories: true

packages:
  LookiKit:
    path: LookiKit

schemes:
  LookiMac:
    build:
      targets:
        LookiMac: all
    run:
      config: Debug

targets:
  LookiMac:
    type: application
    platform: macOS
    deploymentTarget: "26.0"
    sources:
      - path: LookiMac
        excludes:
          - "**/*.entitlements"
          - "Info.plist"
    dependencies:
      - package: LookiKit
        product: LookiKit
    settings:
      base:
        PRODUCT_NAME: LookiMac
        PRODUCT_BUNDLE_IDENTIFIER: fr.lauriat.lookimac
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        SWIFT_VERSION: "6.0"
        SWIFT_STRICT_CONCURRENCY: complete
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        MACOSX_DEPLOYMENT_TARGET: "26.0"
        CODE_SIGN_ENTITLEMENTS: LookiMac/LookiMac.entitlements
        CODE_SIGN_IDENTITY: ""
        CODE_SIGNING_REQUIRED: NO
        CODE_SIGNING_ALLOWED: NO
        ENABLE_HARDENED_RUNTIME: YES
    info:
      path: LookiMac/Info.plist
      properties:
        CFBundleDevelopmentRegion: fr
        CFBundleName: Looki pour Mac
        CFBundleDisplayName: Looki pour Mac
        CFBundleIdentifier: fr.lauriat.lookimac
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        LSMinimumSystemVersion: "26.0"
        LSApplicationCategoryType: public.app-category.photography
        NSHumanReadableCopyright: ""
```

- [ ] **Step 2: Entitlements and asset catalog**

`LookiMac/LookiMac.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.bookmarks.app-scope</key>
    <true/>
</dict>
</plist>
```

`LookiMac/Assets.xcassets/Contents.json`:

```json
{ "info" : { "author" : "xcode", "version" : 1 } }
```

`LookiMac/Assets.xcassets/AppIcon.appiconset/Contents.json` (empty set is valid; icon files come later):

```json
{ "images" : [ { "idiom" : "mac", "scale" : "2x", "size" : "512x512" } ], "info" : { "author" : "xcode", "version" : 1 } }
```

`LookiMac/Info.plist` is generated by xcodegen from `info:` — create an empty plist so the path exists:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

- [ ] **Step 3: KeychainStore**

`LookiMac/Services/KeychainStore.swift`:

```swift
import Foundation
import Security

/// Generic-password item holding the Looki API key. Service is the bundle id.
enum KeychainStore {
    enum KeychainError: Error, LocalizedError {
        case status(OSStatus)
        var errorDescription: String? {
            if case .status(let s) = self { return SecCopyErrorMessageString(s, nil) as String? ?? "Keychain error \(s)" }
            return nil
        }
    }

    private static let service = "fr.lauriat.lookimac"
    private static let account = "api-key"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func readAPIKey() throws -> String? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        switch status {
        case errSecSuccess:
            guard let data = out as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.status(status)
        }
    }

    static func saveAPIKey(_ key: String) throws {
        let data = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let update = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError.status(update) }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    static func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}
```

- [ ] **Step 4: AppModel (credentials part) and app entry**

`LookiMac/Model/AppModel.swift`:

```swift
import Foundation
import Observation
import LookiKit

@MainActor
@Observable
final class AppModel {
    private(set) var apiKey: String?
    private(set) var client: LookiClient?
    let cache: MomentCache

    var needsSetup: Bool { client == nil }

    init(cache: MomentCache = MomentCache(root: MomentCache.defaultRoot())) {
        self.cache = cache
        if let key = try? KeychainStore.readAPIKey(), !key.isEmpty {
            apiKey = key
            client = LookiClient(apiKey: key)
        }
    }

    func setAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try KeychainStore.saveAPIKey(trimmed)
        apiKey = trimmed
        client = LookiClient(apiKey: trimmed)
    }

    func clearAPIKey() throws {
        try KeychainStore.deleteAPIKey()
        apiKey = nil
        client = nil
    }
}
```

`LookiMac/LookiMacApp.swift`:

```swift
import SwiftUI

@main
struct LookiMacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Looki pour Mac") {
            RootView()
                .environment(model)
                .frame(minWidth: 1000, minHeight: 640)
        }
        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
```

`LookiMac/Views/RootView.swift` (placeholder for now):

```swift
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Text(model.needsSetup ? "Configure ta clé API dans Réglages." : "Connecté.")
            .padding()
    }
}
```

`LookiMac/Views/SettingsView.swift` (placeholder, real one in Task 8):

```swift
import SwiftUI

struct SettingsView: View {
    var body: some View { Text("Réglages").padding() }
}
```

- [ ] **Step 5: Generate and build**

Run:

```bash
xcodegen generate
xcodebuild -project LookiMac.xcodeproj -scheme LookiMac -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`. If xcodegen complains about `xcodeVersion`, drop that line. If SwiftPM fails on `.macOS("26.0")`, switch the package platform to `.macOS(.v26)`.

- [ ] **Step 6: Commit**

```bash
git add project.yml LookiMac
git commit -m "feat(app): scaffold LookiMac target with Keychain-backed AppModel"
```

---

### Task 8: Settings — API key, connection test, archive folder, cache purge, import

**Files:**
- Create: `LookiMac/Services/ArchiveFolderBookmark.swift`
- Create: `LookiMac/Services/CredentialsFileImporter.swift`
- Modify: `LookiMac/Model/AppModel.swift` (add archive root, connection test, purge)
- Replace: `LookiMac/Views/SettingsView.swift`

**Interfaces:**
- Consumes: `KeychainStore`, `LookiClient.me()`, `MomentCache.purge()/sizeOnDisk()`.
- Produces:
  - `enum ArchiveFolderBookmark { static func save(_ url: URL) throws; static func load() -> URL?; static func clear() }` (UserDefaults key `archiveRootBookmark`, security-scoped, `startAccessingSecurityScopedResource` handled by caller `withAccess`).
  - `func ArchiveFolderBookmark.withAccess<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T`.
  - `struct CredentialsFile: Decodable { baseUrl: String?; apiKey: String }` and `enum CredentialsFileImporter { static func read(_ url: URL) throws -> CredentialsFile }`.
  - `AppModel`: `var archiveRoot: URL?`, `func chooseArchiveFolder(_ url: URL) throws`, `func testConnection() async -> Result<UserProfile, LookiError>`, `func purgeCache() async throws`, `var cacheSize: Int64` (refreshed by `refreshCacheSize()`).

- [ ] **Step 1: Bookmark and importer services**

`ArchiveFolderBookmark.swift`:

```swift
import Foundation

/// Persists the user-chosen archive folder as a security-scoped bookmark (sandbox).
enum ArchiveFolderBookmark {
    private static let key = "archiveRootBookmark"

    static func save(_ url: URL) throws {
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale { try? save(url) }
        return url
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    /// Runs `body` while the security scope is open.
    static func withAccess<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }
}
```

`CredentialsFileImporter.swift`:

```swift
import Foundation

/// Reads `{ "base_url": ..., "api_key": ... }` as written in ~/.config/looki/credentials.json.
struct CredentialsFile: Decodable {
    let baseUrl: String?
    let apiKey: String
}

enum CredentialsFileImporter {
    static func read(_ url: URL) throws -> CredentialsFile {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(CredentialsFile.self, from: Data(contentsOf: url))
    }
}
```

- [ ] **Step 2: Extend AppModel**

Add to `AppModel`:

```swift
    private(set) var archiveRoot: URL? = ArchiveFolderBookmark.load()
    private(set) var cacheSize: Int64 = 0

    func chooseArchiveFolder(_ url: URL) throws {
        try ArchiveFolderBookmark.save(url)
        archiveRoot = url
    }

    func testConnection() async -> Result<UserProfile, LookiError> {
        guard let client else { return .failure(.missingAPIKey) }
        do { return .success(try await client.me()) }
        catch let e as LookiError { return .failure(e) }
        catch { return .failure(.network(error.localizedDescription)) }
    }

    func refreshCacheSize() async {
        cacheSize = await cache.sizeOnDisk()
    }

    func purgeCache() async throws {
        try await cache.purge()
        await refreshCacheSize()
    }
```

(`import LookiKit` is already present; `UserProfile` and `LookiError` come from it.)

- [ ] **Step 3: SettingsView**

```swift
import SwiftUI
import AppKit
import LookiKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var keyField = ""
    @State private var status: String?
    @State private var statusIsError = false
    @State private var testing = false

    var body: some View {
        Form {
            Section("Compte Looki") {
                SecureField("Clé API (lk-…)", text: $keyField)
                    .textContentType(.password)
                HStack {
                    Button("Enregistrer la clé") { save() }
                        .disabled(keyField.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Tester la connexion") { Task { await test() } }
                        .disabled(model.needsSetup || testing)
                    Button("Importer depuis un fichier…") { importFile() }
                    Spacer()
                    Button("Oublier la clé", role: .destructive) { forget() }
                        .disabled(model.needsSetup)
                }
                if let status {
                    Label(status, systemImage: statusIsError ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(statusIsError ? .red : .green)
                }
                Text("La clé est conservée dans le trousseau macOS, jamais dans un fichier de l'app. Crée-la sur web.looki.ai › API Keys.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Archive") {
                LabeledContent("Dossier") {
                    Text(model.archiveRoot?.path(percentEncoded: false) ?? "Non défini").lineLimit(1).truncationMode(.middle)
                }
                Button("Choisir le dossier…") { chooseFolder() }
                Text("Chaque jour archivé produit un sous-dossier AAAA/MM/JJ avec les médias, journal.md et moments.json.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Cache") {
                LabeledContent("Taille", value: ByteCountFormatter.string(fromByteCount: model.cacheSize, countStyle: .file))
                Button("Vider le cache") { Task { try? await model.purgeCache() } }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
        .task { await model.refreshCacheSize() }
        .onAppear { keyField = model.apiKey ?? "" }
    }

    private func save() {
        do {
            try model.setAPIKey(keyField)
            show("Clé enregistrée.", error: false)
        } catch {
            show("Trousseau : \(error.localizedDescription)", error: true)
        }
    }

    private func forget() {
        do { try model.clearAPIKey(); keyField = ""; show("Clé supprimée.", error: false) }
        catch { show("Trousseau : \(error.localizedDescription)", error: true) }
    }

    private func test() async {
        testing = true; defer { testing = false }
        switch await model.testConnection() {
        case .success(let user):
            let name = user.displayName.isEmpty ? "compte vérifié" : user.displayName
            show("Connexion OK — \(name) (\(user.tz ?? "fuseau inconnu")).", error: false)
        case .failure(let e):
            show(e.userMessage, error: true)
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.directoryURL = URL(filePath: NSHomeDirectory()).appending(path: ".config/looki")
        panel.showsHiddenFiles = true
        panel.message = "Sélectionne credentials.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let creds = try CredentialsFileImporter.read(url)
            keyField = creds.apiKey
            save()
        } catch {
            show("Fichier illisible : \(error.localizedDescription)", error: true)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.chooseArchiveFolder(url) }
        catch { show("Impossible de mémoriser ce dossier : \(error.localizedDescription)", error: true) }
    }

    private func show(_ text: String, error: Bool) { status = text; statusIsError = error }
}
```

- [ ] **Step 4: Build**

Run: `xcodegen generate && xcodebuild -project LookiMac.xcodeproj -scheme LookiMac -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual smoke test**

Run: `open build/Build/Products/Debug/LookiMac.app`, open Réglages (⌘,), paste the key, "Tester la connexion" must print `Connexion OK — … (+02:00)`. Choose an archive folder, quit and relaunch: the folder path must persist.

- [ ] **Step 6: Commit**

```bash
git add LookiMac
git commit -m "feat(app): add settings with Keychain key, connection test and archive folder"
```

---

### Task 9: Day loading, month marks and the calendar sidebar

**Files:**
- Create: `LookiMac/Model/DayState.swift`
- Create: `LookiMac/Model/Banner.swift`
- Modify: `LookiMac/Model/AppModel.swift` (selection, day loading, month index)
- Create: `LookiMac/Views/CalendarSidebarView.swift`
- Replace: `LookiMac/Views/RootView.swift` (three columns; content and detail are placeholders until Tasks 10–11)
- Create: `LookiMac/Views/EmptyStateView.swift`

**Interfaces:**
- Consumes: `LookiClient.moments(on:)`, `MomentCache.day/store/fetchedDays`, `DayKey`.
- Produces:
  - `enum DayState: Equatable { idle, loading, loaded([Moment]), empty, failed(LookiError) }`
  - `struct Banner: Equatable, Identifiable { id: UUID; text: String; isError: Bool; showsSettings: Bool }`
  - `AppModel`: `var selectedDay: DayKey`, `var dayState: DayState`, `var visibleMonth: (year: Int, month: Int)`, `var monthMarks: [DayKey: Int]`, `var selectedMoment: Moment?`, `var banner: Banner?`, `func select(day: DayKey)`, `func reloadSelectedDay(force: Bool = false) async`, `func showMonth(year: Int, month: Int)`, `func refreshMonthMarks() async`, `var localTimeZone: TimeZone`, `static func today(in tz: TimeZone) -> DayKey`.

- [ ] **Step 1: DayState and Banner**

```swift
// DayState.swift
import LookiKit

enum DayState: Equatable {
    case idle
    case loading
    case loaded([Moment])
    case empty
    case failed(LookiError)

    var moments: [Moment] { if case .loaded(let m) = self { m } else { [] } }
}
```

```swift
// Banner.swift
import Foundation

struct Banner: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
    let showsSettings: Bool
}
```

- [ ] **Step 2: Extend AppModel with selection and loading**

Add to `AppModel`:

```swift
    var localTimeZone: TimeZone { TimeZone.current }
    static func today(in tz: TimeZone) -> DayKey { DayKey(date: Date(), timeZone: tz) }

    var selectedDay: DayKey = AppModel.today(in: .current)
    private(set) var dayState: DayState = .idle
    private(set) var visibleMonth: (year: Int, month: Int) = (AppModel.today(in: .current).year, AppModel.today(in: .current).month)
    private(set) var monthMarks: [DayKey: Int] = [:]
    var selectedMoment: Moment?
    var banner: Banner?

    private var dayLoadTask: Task<Void, Never>?
    private var monthTask: Task<Void, Never>?

    func select(day: DayKey) {
        guard day != selectedDay || dayState == .idle else { return }
        selectedDay = day
        selectedMoment = nil
        if (day.year, day.month) != visibleMonth { showMonth(year: day.year, month: day.month) }
        dayLoadTask?.cancel()
        dayLoadTask = Task { await reloadSelectedDay() }
    }

    /// Cache first, then network (unless the cached record is from today and `force` is false).
    func reloadSelectedDay(force: Bool = false) async {
        let day = selectedDay
        if !force, let cached = await cache.day(day) {
            apply(cached.moments, for: day)
            // A cached "today" may be incomplete: refresh silently in the background.
            if day != Self.today(in: localTimeZone) { return }
        } else {
            dayState = .loading
        }
        guard let client else { dayState = .failed(.missingAPIKey); return }
        do {
            let fresh = try await client.moments(on: day)
            guard !Task.isCancelled, day == selectedDay else { return }
            try? await cache.store(fresh, for: day)
            apply(fresh, for: day)
            monthMarks[day] = fresh.count
            banner = nil
        } catch let e as LookiError {
            guard day == selectedDay else { return }
            if case .loaded = dayState { banner = Banner(text: e.userMessage, isError: true, showsSettings: e == .unauthorized) }
            else { dayState = .failed(e) }
        } catch {
            if case .loaded = dayState {} else { dayState = .failed(.network(error.localizedDescription)) }
        }
    }

    private func apply(_ moments: [Moment], for day: DayKey) {
        guard day == selectedDay else { return }
        dayState = moments.isEmpty ? .empty : .loaded(moments.sorted { $0.startTime < $1.startTime })
    }

    func showMonth(year: Int, month: Int) {
        visibleMonth = (year, month)
        monthTask?.cancel()
        monthTask = Task { await refreshMonthMarks() }
    }

    /// Marks from the cache immediately; then fetches any day of the month not yet cached,
    /// oldest first, never beyond today, one request at a time.
    func refreshMonthMarks() async {
        let (year, month) = visibleMonth
        monthMarks = await cache.fetchedDays(year: year, month: month)
        guard let client else { return }
        let today = Self.today(in: localTimeZone)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = localTimeZone
        let first = DayKey(year: year, month: month, day: 1)
        let count = cal.range(of: .day, in: .month, for: first.date(in: localTimeZone))!.count
        for d in 1...count {
            let key = DayKey(year: year, month: month, day: d)
            if key > today || monthMarks[key] != nil { continue }
            if Task.isCancelled || visibleMonth != (year, month) { return }
            do {
                let moments = try await client.moments(on: key)
                try? await cache.store(moments, for: key)
                monthMarks[key] = moments.count
            } catch {
                return   // stop scanning on the first error; the day view reports it when selected
            }
        }
    }
```

Swift 6 note: tuples of `Int` are `Sendable`; comparing `visibleMonth != (year, month)` works because tuple equality is synthesized for arity 2.

- [ ] **Step 3: Calendar sidebar**

```swift
import SwiftUI
import LookiKit

struct CalendarSidebarView: View {
    @Environment(AppModel.self) private var model

    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = model.localTimeZone; c.locale = Locale(identifier: "fr_FR"); return c }

    var body: some View {
        VStack(spacing: 12) {
            header
            weekdayRow
            grid
            Spacer()
        }
        .padding(12)
        .navigationTitle("Looki")
    }

    private var header: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(monthTitle).font(.headline)
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .disabled(isCurrentMonth)
        }
        .buttonStyle(.borderless)
        .overlay(alignment: .bottom) {
            Button("Aujourd'hui") { model.select(day: AppModel.today(in: model.localTimeZone)) }
                .font(.caption).buttonStyle(.link).offset(y: 22)
        }
        .padding(.bottom, 12)
    }

    private var monthTitle: String {
        let f = DateFormatter(); f.calendar = cal; f.locale = cal.locale; f.timeZone = cal.timeZone; f.dateFormat = "LLLL yyyy"
        return f.string(from: firstOfMonth).capitalized
    }

    private var firstOfMonth: Date {
        DayKey(year: model.visibleMonth.year, month: model.visibleMonth.month, day: 1).date(in: model.localTimeZone)
    }

    private var isCurrentMonth: Bool {
        let t = AppModel.today(in: model.localTimeZone)
        return (t.year, t.month) == model.visibleMonth
    }

    private var weekdayRow: some View {
        let symbols = cal.veryShortStandaloneWeekdaySymbols   // Sunday-first
        let ordered = Array(symbols[1...]) + [symbols[0]]      // Monday-first
        return HStack { ForEach(ordered, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity) } }
    }

    private var grid: some View {
        let days = cal.range(of: .day, in: .month, for: firstOfMonth)!.count
        let weekday = cal.component(.weekday, from: firstOfMonth)   // 1 = Sunday
        let leading = (weekday + 5) % 7                              // Monday-first offset
        let today = AppModel.today(in: model.localTimeZone)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
            ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 32) }
            ForEach(1...days, id: \.self) { d in
                let key = DayKey(year: model.visibleMonth.year, month: model.visibleMonth.month, day: d)
                DayCell(day: d, count: model.monthMarks[key], isSelected: key == model.selectedDay, isFuture: key > today)
                    .onTapGesture { if key <= today { model.select(day: key) } }
            }
        }
    }

    private func shift(_ delta: Int) {
        let date = cal.date(byAdding: .month, value: delta, to: firstOfMonth)!
        let c = cal.dateComponents([.year, .month], from: date)
        model.showMonth(year: c.year!, month: c.month!)
    }
}

private struct DayCell: View {
    let day: Int
    let count: Int?        // nil = not fetched yet, 0 = fetched and empty
    let isSelected: Bool
    let isFuture: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text("\(day)").font(.callout.monospacedDigit())
            Circle().frame(width: 5, height: 5)
                .foregroundStyle((count ?? 0) > 0 ? Color.accentColor : .clear)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
        .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color.accentColor.opacity(0.2) : .clear))
        .foregroundStyle(isFuture ? .tertiary : (count == 0 ? .secondary : .primary))
        .contentShape(Rectangle())
        .accessibilityLabel(count.map { "\(day), \($0) moments" } ?? "\(day)")
    }
}
```

- [ ] **Step 4: RootView and EmptyStateView**

```swift
// EmptyStateView.swift
import SwiftUI

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var detail: String? = nil
    var body: some View {
        ContentUnavailableView { Label(title, systemImage: systemImage) } description: { if let detail { Text(detail) } }
    }
}
```

```swift
// RootView.swift
import SwiftUI
import LookiKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            CalendarSidebarView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 320)
        } content: {
            Text("Timeline (Tâche 10)")   // replaced in Task 10
                .navigationSplitViewColumnWidth(min: 360, ideal: 420)
        } detail: {
            EmptyStateView(title: "Sélectionne un moment", systemImage: "photo.on.rectangle")
        }
        .safeAreaInset(edge: .top) {
            if let banner = model.banner {
                HStack {
                    Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "info.circle")
                    Text(banner.text)
                    Spacer()
                    if banner.showsSettings { Button("Réglages…") { openSettings() } }
                    Button { model.banner = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                .padding(8)
                .background(banner.isError ? Color.red.opacity(0.15) : Color.yellow.opacity(0.15))
            }
        }
        .task {
            if model.needsSetup {
                model.banner = Banner(text: "Aucune clé API : ouvre les Réglages pour te connecter à Looki.", isError: true, showsSettings: true)
                openSettings()
            } else {
                model.select(day: model.selectedDay)
            }
        }
        .onChange(of: model.needsSetup) { _, needs in
            if !needs { model.banner = nil; model.select(day: model.selectedDay) }
        }
    }
}
```

- [ ] **Step 5: Build and smoke test**

Run the build command. Expected `** BUILD SUCCEEDED **`. Launch: the calendar shows September 2026, dots appear progressively on days with moments (one request per day, oldest first), today is selected. Navigating to a past month fills its marks; the "›" button is disabled on the current month.

- [ ] **Step 6: Commit**

```bash
git add LookiMac
git commit -m "feat(app): add day loading, month marks and calendar sidebar"
```

---

### Task 10: Day timeline with thumbnails

**Files:**
- Create: `LookiMac/Services/ThumbnailLoader.swift`
- Create: `LookiMac/Views/MomentRowView.swift`
- Create: `LookiMac/Views/DayTimelineView.swift`
- Modify: `LookiMac/Views/RootView.swift` (content column → `DayTimelineView`)

**Interfaces:**
- Consumes: `DayState`, `MomentCache.thumbnail/storeThumbnail`, `Moment`, `LookiClient.moment(id:)`.
- Produces:
  - `@MainActor @Observable final class ThumbnailLoader` with `init(cache: MomentCache, freshMoment: @Sendable @escaping (String) async throws -> Moment)`, `func image(for moment: Moment) async -> NSImage?` (cache → download image / grab a frame from the video with `AVAssetImageGenerator` → JPEG into cache), in-memory `NSCache`.
  - `AppModel`: `let thumbnails: ThumbnailLoader` (constructed in `init` after `client` is known; rebuilt in `setAPIKey`), `func freshMoment(id: String) async throws -> Moment`.
  - `struct MomentRowView: View { let moment: Moment }`, `struct DayTimelineView: View`.

- [ ] **Step 1: ThumbnailLoader**

```swift
import AppKit
import AVFoundation
import Observation
import LookiKit

@MainActor
@Observable
final class ThumbnailLoader {
    typealias FreshMoment = @Sendable (String) async throws -> Moment

    private let cache: MomentCache
    private let freshMoment: FreshMoment
    private let memory = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    init(cache: MomentCache, freshMoment: @escaping FreshMoment) {
        self.cache = cache
        self.freshMoment = freshMoment
        memory.countLimit = 400
    }

    func image(for moment: Moment) async -> NSImage? {
        guard let file = moment.coverFile else { return nil }
        let key = file.id
        if let img = memory.object(forKey: key as NSString) { return img }
        if let task = inFlight[key] { return await task.value }
        let task = Task<NSImage?, Never> { [cache, freshMoment] in
            if let data = await cache.thumbnail(for: key), let img = NSImage(data: data) { return img }
            // Prefer the URL we already have (list call); fall back to a fresh detail if it is gone.
            var url = file.file.temporaryURL
            if url == nil { url = try? await freshMoment(moment.id).coverFile?.file.temporaryURL }
            guard let url else { return nil }
            guard let jpeg = await Self.makeJPEG(from: url, mediaType: file.file.mediaType) else { return nil }
            try? await cache.storeThumbnail(jpeg, for: key)
            return NSImage(data: jpeg)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { memory.setObject(result, forKey: key as NSString) }
        return result
    }

    /// Downloads an image, or grabs the first frame of a remote video, and returns ~320 px wide JPEG data.
    nonisolated private static func makeJPEG(from url: URL, mediaType: MediaType) async -> Data? {
        let cgImage: CGImage?
        switch mediaType {
        case .image, .unknown:
            guard let (data, _) = try? await URLSession.shared.data(from: url), let img = NSImage(data: data) else { return nil }
            cgImage = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        case .video:
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            cgImage = try? await generator.image(at: .init(seconds: 0.5, preferredTimescale: 600)).image
        }
        guard let cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}
```

Add to `AppModel`:

```swift
    private(set) var thumbnails: ThumbnailLoader

    func freshMoment(id: String) async throws -> Moment {
        guard let client else { throw LookiError.missingAPIKey }
        return try await client.moment(id: id)
    }
```

and in `init`, after `client` is set: `thumbnails = ThumbnailLoader(cache: cache, freshMoment: { [client] id in guard let client else { throw LookiError.missingAPIKey }; return try await client.moment(id: id) })`. In `setAPIKey`, rebuild `thumbnails` the same way with the new client. Since `thumbnails` is a `let`-like stored property initialised in `init`, declare it `private(set) var` and assign it in both places.

- [ ] **Step 2: Row and timeline views**

```swift
// MomentRowView.swift
import SwiftUI
import LookiKit

struct MomentRowView: View {
    @Environment(AppModel.self) private var model
    let moment: Moment
    @State private var thumb: NSImage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                if let thumb { Image(nsImage: thumb).resizable().scaledToFill() }
                else { Image(systemName: moment.mediaTypes.contains(.video) ? "video" : "photo").foregroundStyle(.secondary) }
            }
            .frame(width: 96, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(timeRange).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text(moment.title).font(.headline).lineLimit(2)
                if let place = moment.coverFile?.location?.shortLabel, !place.isEmpty {
                    Label(place, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    ForEach(moment.mediaTypes, id: \.self) { t in
                        Image(systemName: t == .video ? "video.fill" : "photo.fill").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .task(id: moment.coverFile?.id) { thumb = await model.thumbnails.image(for: moment) }
    }

    private var timeRange: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.timeZone = moment.timeZone; f.dateFormat = "HH:mm"
        return "\(f.string(from: moment.startTime)) – \(f.string(from: moment.endTime))"
    }
}
```

```swift
// DayTimelineView.swift
import SwiftUI
import LookiKit

struct DayTimelineView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.dayState {
            case .idle, .loading:
                ProgressView("Chargement…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                EmptyStateView(title: "Aucun moment ce jour", systemImage: "moon.zzz", detail: "Looki n'a rien capturé le \(model.selectedDay.string).")
            case .failed(let e):
                EmptyStateView(title: e.userMessage, systemImage: "wifi.exclamationmark", detail: "Vérifie ta connexion ou ta clé API.")
                    .overlay(alignment: .bottom) { Button("Réessayer") { Task { await model.reloadSelectedDay(force: true) } }.padding() }
            case .loaded(let moments):
                List(moments, selection: $model.selectedMoment) { m in
                    MomentRowView(moment: m).tag(m)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(dayTitle)
        .navigationSubtitle(subtitle)
    }

    private var dayTitle: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.timeZone = model.localTimeZone; f.dateFormat = "EEEE d MMMM yyyy"
        return f.string(from: model.selectedDay.date(in: model.localTimeZone)).capitalized
    }

    private var subtitle: String {
        let n = model.dayState.moments.count
        return n == 0 ? "" : "\(n) moment\(n > 1 ? "s" : "")"
    }
}
```

In `RootView`, replace the content placeholder with `DayTimelineView().navigationSplitViewColumnWidth(min: 360, ideal: 420)`.

- [ ] **Step 3: Build and smoke test**

Build must succeed. Launch: today's moments list with thumbnails appearing progressively; selecting a row highlights it. Relaunch: thumbnails come from the cache instantly (check `~/Library/Containers/fr.lauriat.lookimac/Data/Library/Caches/fr.lauriat.lookimac/thumbs/`).

- [ ] **Step 4: Commit**

```bash
git add LookiMac
git commit -m "feat(app): add day timeline with cached thumbnails"
```

---

### Task 11: Moment detail with video playback

**Files:**
- Create: `LookiMac/Views/MomentDetailView.swift`
- Modify: `LookiMac/Views/RootView.swift` (detail column)

**Interfaces:**
- Consumes: `AppModel.selectedMoment`, `AppModel.freshMoment(id:)`, `AVKit.VideoPlayer`.
- Produces: `struct MomentDetailView: View { let moment: Moment }`.

- [ ] **Step 1: Detail view**

```swift
import SwiftUI
import AVKit
import LookiKit

struct MomentDetailView: View {
    @Environment(AppModel.self) private var model
    let moment: Moment

    @State private var player: AVPlayer?
    @State private var image: NSImage?
    @State private var mediaError: String?
    @State private var retried = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                media
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4/3, contentMode: .fit)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(moment.title).font(.title2.bold())
                HStack(spacing: 16) {
                    Label(timeRange, systemImage: "clock")
                    Label(duration, systemImage: "timer")
                }
                .font(.callout).foregroundStyle(.secondary)
                if let loc = moment.coverFile?.location {
                    Label(fullAddress(loc), systemImage: "mappin.and.ellipse").font(.callout).foregroundStyle(.secondary)
                }
                Divider()
                Text(moment.description).font(.body).textSelection(.enabled)
                if let mediaError {
                    Label(mediaError, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .navigationTitle(moment.title)
        .task(id: moment.id) { await loadMedia() }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder private var media: some View {
        if let player {
            VideoPlayer(player: player)
        } else if let image {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Always re-fetch the detail: list URLs may have expired since they were loaded.
    private func loadMedia() async {
        player?.pause(); player = nil; image = nil; mediaError = nil; retried = false
        do {
            let fresh = try await model.freshMoment(id: moment.id)
            guard let file = fresh.coverFile?.file, let url = file.temporaryURL else {
                mediaError = "Aucun média disponible pour ce moment."; return
            }
            switch file.mediaType {
            case .video:
                let item = AVPlayerItem(url: url)
                let p = AVPlayer(playerItem: item)
                player = p
                observeFailure(of: item)
            case .image, .unknown:
                let (data, _) = try await URLSession.shared.data(from: url)
                image = NSImage(data: data)
                if image == nil { mediaError = "Image illisible." }
            }
        } catch let e as LookiError {
            mediaError = e.userMessage
        } catch {
            mediaError = error.localizedDescription
        }
    }

    /// If the signed URL expired between fetch and playback, fetch once more; then give up with a message.
    private func observeFailure(of item: AVPlayerItem) {
        Task { @MainActor in
            for await status in item.publisher(for: \.status).values {
                if status == .failed {
                    if !retried { retried = true; await loadMedia() }
                    else { mediaError = "La vidéo n'a pas pu être lue (lien expiré ?)." }
                    return
                }
                if status == .readyToPlay { return }
            }
        }
    }

    private var timeRange: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.timeZone = moment.timeZone; f.dateFormat = "HH:mm"
        return "\(f.string(from: moment.startTime)) – \(f.string(from: moment.endTime))"
    }

    private var duration: String {
        let mn = Int(moment.duration / 60)
        return mn >= 60 ? "\(mn / 60) h \(String(format: "%02d", mn % 60))" : "\(mn) min"
    }

    private func fullAddress(_ l: Location) -> String {
        [l.street, l.subLocality, l.locality].compactMap { $0 }.uniqued().joined(separator: " · ")
    }
}
```

`uniqued()` lives in LookiKit as an internal extension; make it `public` in `JournalRenderer.swift` (`public extension Array where Element: Hashable { func uniqued() -> [Element] }`) so the app can use it.

In `RootView`, the detail column becomes:

```swift
        } detail: {
            if let m = model.selectedMoment {
                MomentDetailView(moment: m)
            } else {
                EmptyStateView(title: "Sélectionne un moment", systemImage: "photo.on.rectangle")
            }
        }
```

- [ ] **Step 2: Build and smoke test**

Build must succeed. Launch: click a video moment → the player shows the clip and plays; click an image moment → the photo appears. Select a moment, wait past the URL lifetime (or simulate by cutting Wi-Fi) → a French error appears instead of a spinner forever.

- [ ] **Step 3: Commit**

```bash
git add LookiMac LookiKit
git commit -m "feat(app): add moment detail with video playback"
```

---

### Task 12: Search mode with pagination

**Files:**
- Modify: `LookiMac/Model/AppModel.swift` (search state)
- Create: `LookiMac/Views/SearchResultsView.swift`
- Modify: `LookiMac/Views/RootView.swift` (toolbar search field, content switch)

**Interfaces:**
- Consumes: `LookiClient.search(query:page:pageSize:)`, `SearchPage`, `MomentRowView`.
- Produces: `AppModel`: `var searchQuery: String`, `private(set) var searchResults: [Moment]`, `private(set) var searchHasMore: Bool`, `private(set) var isSearching: Bool`, `private(set) var searchError: LookiError?`, `var isSearchMode: Bool` (`!searchQuery.trimmed.isEmpty`), `func runSearch() async`, `func loadMoreSearch() async`, `func clearSearch()`.

- [ ] **Step 1: Search state in AppModel**

```swift
    var searchQuery: String = ""
    private(set) var searchResults: [Moment] = []
    private(set) var searchHasMore = false
    private(set) var isSearching = false
    private(set) var searchError: LookiError?
    private var searchPage = 0
    private var searchTask: Task<Void, Never>?
    private let searchPageSize = 20

    var isSearchMode: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Debounced by the caller (`.task(id:)` in the view); resets pagination.
    func runSearch() async {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        searchTask?.cancel()
        guard !q.isEmpty else { clearSearch(); return }
        guard let client else { searchError = .missingAPIKey; return }
        searchResults = []; searchPage = 0; searchHasMore = false; searchError = nil
        isSearching = true
        defer { isSearching = false }
        do {
            let page = try await client.search(query: q, page: 1, pageSize: searchPageSize)
            guard !Task.isCancelled, q == searchQuery.trimmingCharacters(in: .whitespaces) else { return }
            searchResults = page.items; searchHasMore = page.hasMore; searchPage = 1
        } catch let e as LookiError { searchError = e }
        catch { searchError = .network(error.localizedDescription) }
    }

    func loadMoreSearch() async {
        guard searchHasMore, !isSearching, let client else { return }
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        isSearching = true
        defer { isSearching = false }
        do {
            let page = try await client.search(query: q, page: searchPage + 1, pageSize: searchPageSize)
            guard q == searchQuery.trimmingCharacters(in: .whitespaces) else { return }
            let known = Set(searchResults.map(\.id))
            searchResults += page.items.filter { !known.contains($0.id) }
            searchHasMore = page.hasMore; searchPage += 1
        } catch let e as LookiError { searchError = e }
        catch { searchError = .network(error.localizedDescription) }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchQuery = ""; searchResults = []; searchHasMore = false; searchError = nil; searchPage = 0
    }
```

- [ ] **Step 2: SearchResultsView**

```swift
import SwiftUI
import LookiKit

struct SearchResultsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if let e = model.searchError {
                EmptyStateView(title: e.userMessage, systemImage: "exclamationmark.magnifyingglass")
            } else if model.searchResults.isEmpty && !model.isSearching {
                EmptyStateView(title: "Aucun souvenir trouvé", systemImage: "magnifyingglass", detail: "Essaie d'autres mots : lieu, activité, objet, personne.")
            } else {
                List(selection: $model.selectedMoment) {
                    ForEach(model.searchResults) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            MomentRowView(moment: m)
                            Text(m.date.string).font(.caption2).foregroundStyle(.tertiary)
                        }
                        .tag(m)
                    }
                    if model.searchHasMore {
                        HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                            .task { await model.loadMoreSearch() }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Recherche")
        .navigationSubtitle(model.isSearching && model.searchResults.isEmpty ? "Recherche en cours…" : "\(model.searchResults.count) résultat\(model.searchResults.count > 1 ? "s" : "")")
        .task(id: model.searchQuery) {
            try? await Task.sleep(for: .milliseconds(350))   // debounce typing
            guard !Task.isCancelled else { return }
            await model.runSearch()
        }
    }
}
```

- [ ] **Step 3: Toolbar and content switch in RootView**

Replace the `content:` closure with:

```swift
        } content: {
            Group {
                if model.isSearchMode { SearchResultsView() } else { DayTimelineView() }
            }
            .navigationSplitViewColumnWidth(min: 360, ideal: 420)
```

and add after `.safeAreaInset(...)`:

```swift
        .searchable(text: $model.searchQuery, placement: .toolbar, prompt: "Rechercher un souvenir…")
        .onSubmit(of: .search) { Task { await model.runSearch() } }
```

`@Bindable var model = model` is already declared at the top of `body`, so `$model.searchQuery` binds.

- [ ] **Step 4: Build and smoke test**

Build must succeed. Type "café" in the search field: results replace the timeline after a short delay, each row shows its date, scrolling to the bottom loads more when `has_more` is true. Clearing the field returns to the selected day. Clicking a result shows it in the detail column.

- [ ] **Step 5: Commit**

```bash
git add LookiMac
git commit -m "feat(app): add semantic search with pagination"
```

---

### Task 13: Archive command with progress

**Files:**
- Modify: `LookiMac/Model/AppModel.swift` (archive state + command)
- Create: `LookiMac/Views/ArchiveProgressView.swift`
- Modify: `LookiMac/Views/RootView.swift` (toolbar buttons, sheet)
- Modify: `LookiMac/Views/MomentDetailView.swift` ("Révéler dans l'archive")

**Interfaces:**
- Consumes: `DayArchiver`, `ArchiveEvent`, `ArchiveFolderBookmark.withAccess`, `NSWorkspace`.
- Produces: `AppModel`: `struct ArchiveProgress: Equatable { total: Int; done: Int; skipped: Int; lastMessage: String; folder: URL?; finished: Bool; error: String? }`, `private(set) var archiveProgress: ArchiveProgress?`, `var isArchiving: Bool`, `func archiveSelectedDay()`, `func cancelArchive()`, `func openArchiveRoot()`, `func archivedFolder(for day: DayKey) -> URL?` (exists on disk), `func reveal(_ url: URL)`.

- [ ] **Step 1: Archive state and command in AppModel**

```swift
    struct ArchiveProgress: Equatable {
        var total = 0
        var done = 0
        var skipped = 0
        var lastMessage = ""
        var folder: URL?
        var finished = false
        var error: String?
    }

    private(set) var archiveProgress: ArchiveProgress?
    private var archiveTask: Task<Void, Never>?
    var isArchiving: Bool { archiveProgress != nil && archiveProgress?.finished == false && archiveProgress?.error == nil }

    func archiveSelectedDay() {
        guard let client, let root = archiveRoot else {
            banner = Banner(text: archiveRoot == nil ? "Choisis d'abord un dossier d'archive dans les Réglages." : LookiError.missingAPIKey.userMessage, isError: true, showsSettings: true)
            return
        }
        let moments = dayState.moments
        guard !moments.isEmpty else { banner = Banner(text: "Rien à archiver pour ce jour.", isError: false, showsSettings: false); return }
        let day = selectedDay
        archiveProgress = ArchiveProgress(total: moments.count)
        archiveTask = Task {
            let archiver = DayArchiver(client: client)
            // Keep the security scope open for the whole run.
            let ok = root.startAccessingSecurityScopedResource()
            defer { if ok { root.stopAccessingSecurityScopedResource() } }
            do {
                for try await event in archiver.archive(day: day, moments: moments, into: root) {
                    switch event {
                    case .started(let total): archiveProgress?.total = total
                    case .downloaded(_, let name): archiveProgress?.done += 1; archiveProgress?.lastMessage = name
                    case .skipped(_, let reason): archiveProgress?.done += 1; archiveProgress?.skipped += 1; archiveProgress?.lastMessage = reason
                    case .wroteJournal: archiveProgress?.lastMessage = "journal.md"
                    case .finished(let folder): archiveProgress?.folder = folder; archiveProgress?.finished = true
                    }
                }
            } catch is CancellationError {
                archiveProgress = nil
            } catch {
                archiveProgress?.error = (error as? LookiError)?.userMessage ?? error.localizedDescription
            }
        }
    }

    func cancelArchive() { archiveTask?.cancel(); archiveProgress = nil }
    func dismissArchiveProgress() { archiveProgress = nil }

    func archivedFolder(for day: DayKey) -> URL? {
        guard let root = archiveRoot else { return nil }
        let folder = DayArchiver.folder(for: day, in: root)
        let exists = (try? ArchiveFolderBookmark.withAccess(root) { _ in FileManager.default.fileExists(atPath: folder.appending(path: "journal.md").path()) }) ?? false
        return exists ? folder : nil
    }

    func openArchiveRoot() {
        guard let root = archiveRoot else { return }
        _ = try? ArchiveFolderBookmark.withAccess(root) { NSWorkspace.shared.open($0) }
    }

    func reveal(_ url: URL) {
        guard let root = archiveRoot else { return }
        _ = try? ArchiveFolderBookmark.withAccess(root) { _ in NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
```

Add `import AppKit` at the top of `AppModel.swift`.

- [ ] **Step 2: Progress sheet**

```swift
import SwiftUI

struct ArchiveProgressView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let p = model.archiveProgress {
            VStack(alignment: .leading, spacing: 12) {
                Text(p.finished ? "Archive terminée" : (p.error == nil ? "Archivage en cours…" : "Archivage interrompu")).font(.headline)
                ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                Text("\(p.done)/\(p.total) · \(p.skipped) ignoré\(p.skipped > 1 ? "s" : "") · \(p.lastMessage)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let error = p.error { Text(error).foregroundStyle(.red).font(.callout) }
                HStack {
                    Spacer()
                    if p.finished || p.error != nil {
                        if let folder = p.folder { Button("Afficher dans le Finder") { model.reveal(folder) } }
                        Button("Fermer") { model.dismissArchiveProgress() }.keyboardShortcut(.defaultAction)
                    } else {
                        Button("Annuler", role: .cancel) { model.cancelArchive() }
                    }
                }
            }
            .padding(20)
            .frame(width: 420)
        }
    }
}
```

- [ ] **Step 3: Toolbar and sheet in RootView; reveal button in detail**

Add to `RootView` after `.searchable(...)`:

```swift
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.archiveSelectedDay()
                } label: { Label("Archiver ce jour", systemImage: "arrow.down.doc") }
                .disabled(model.isSearchMode || model.dayState.moments.isEmpty || model.isArchiving)
                .help("Télécharge les médias du jour et écrit journal.md dans le dossier d'archive")

                Button { model.openArchiveRoot() } label: { Label("Dossier d'archive", systemImage: "folder") }
                    .disabled(model.archiveRoot == nil)
            }
        }
        .sheet(isPresented: Binding(get: { model.archiveProgress != nil }, set: { if !$0 { model.dismissArchiveProgress() } })) {
            ArchiveProgressView().environment(model)
        }
```

In `MomentDetailView`, below the address label add:

```swift
                if let folder = model.archivedFolder(for: moment.date) {
                    Button { model.reveal(folder) } label: { Label("Révéler dans l'archive", systemImage: "folder.badge.checkmark") }
                        .buttonStyle(.link)
                }
```

- [ ] **Step 4: Build and smoke test**

Build must succeed. Choose an archive folder in Réglages, select today, click "Archiver ce jour": the sheet counts down, then "Afficher dans le Finder" opens `<dossier>/2026/09/05/` containing one media file per moment, `journal.md` and `moments.json`. Running it again skips every file (`déjà archivé`) and finishes in a second. The detail view now shows "Révéler dans l'archive" for moments of that day.

- [ ] **Step 5: Commit**

```bash
git add LookiMac
git commit -m "feat(app): add day archive command with progress sheet"
```

---

### Task 14: Release script, README, first signed DMG

**Files:**
- Create: `Scripts/release.sh`
- Create: `README.md`
- Modify: `TODOS.md`, `MEMORY.md`, `CHANGES.md` (doc journals, gitignored — update anyway)

**Interfaces:**
- Consumes: `project.yml` (`MARKETING_VERSION: "0.1.0"`), the `LookiMac` scheme.
- Produces: `release/LookiMac-<version>.dmg`, signed with `Developer ID Application: Vincent LAURIAT (KFLACS69T9)`, notarized via keychain profile `AppliMacVincentGithub`, stapled.

- [ ] **Step 1: Write Scripts/release.sh**

Start from `~/DevApps/Templates/Scripts/release-simple.sh` (identical logic) with these exact changes: `MoveApps` → `LookiMac` everywhere (`-project LookiMac.xcodeproj -scheme LookiMac`, `APP="$ROOT/build/Build/Products/Release/LookiMac.app"`, `STAGING="$STAGING_DIR/LookiMac.app"`, `DMG="$RELEASE_DIR/LookiMac-$VERSION.dmg"`, `-volname "Looki pour Mac $VERSION"`); delete the whole "Codesigning Sparkle.framework nested binaries" block and the "nested MoveAppsCore.framework / MoveAppsUI.framework" block (LookiKit is linked statically, the bundle has no nested frameworks); keep `codesign_ts` with its 5 retries, the `ditto --norsrc --noextattr --noacl` staging, `hdiutil create` into `release/`, notarize + staple, and the `SKIP_NOTARIZE=1` dry-run path. Replace the final "v1 note" echo with: `echo "Vérifie : spctl -a -t exec -vv <app>  &&  xcrun stapler validate $DMG"`. Header comment: describe Looki pour Mac, keep the prerequisites paragraph verbatim.

```bash
chmod +x Scripts/release.sh
```

- [ ] **Step 2: README.md**

```markdown
# Looki pour Mac

![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)

Application macOS native (SwiftUI) pour revoir, rechercher et archiver les
moments capturés par une caméra Looki L1, via l'API ouverte de Looki
(lecture seule). Outil personnel d'un seul développeur, publié par souci de
transparence — pas un produit avec support.

## Fonctionnalités

| Section | Contenu |
|---|---|
| **Calendrier** | Mois avec les jours marqués dès qu'ils contiennent des moments. |
| **Journée** | Timeline des moments : heure, titre, lieu, vignette, type de média. |
| **Détail** | Lecture de la vidéo ou de la photo du moment, description complète, adresse. |
| **Recherche** | Recherche sémantique dans tous les souvenirs, avec pagination. |
| **Archive** | « Archiver ce jour » télécharge les médias et écrit `journal.md` + `moments.json` dans `AAAA/MM/JJ/`. |
| **Réglages** | Clé API dans le trousseau, test de connexion, dossier d'archive, purge du cache. |

## Installation

Télécharger `LookiMac-<version>.dmg` depuis la page Releases, glisser l'app
dans Applications. DMG signé Developer ID et notarisé.

## Prérequis

- macOS 26 ou plus récent.
- Une clé API Looki : web.looki.ai › API Keys (elle ne s'affiche qu'une fois).

## Compiler depuis les sources

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project LookiMac.xcodeproj -scheme LookiMac -configuration Debug build
cd LookiKit && swift test
```

## Arborescence

```
LookiKit/     package Swift : client API, modèles, cache, journal Markdown, archiveur (testé)
LookiMac/     app SwiftUI : fenêtre trois colonnes, réglages, trousseau, archive
Scripts/      release.sh — build, signature, notarisation, DMG
docs/         spec et plan d'implémentation
```

## Confidentialité

La clé API vit dans le trousseau macOS. Les métadonnées et vignettes sont
mises en cache dans le conteneur de l'app ; les liens vidéo signés ne sont
jamais écrits sur disque. L'archive est écrite uniquement dans le dossier que
vous choisissez. Aucune autre connexion réseau que `open.looki.ai` et les URL
de médias qu'il renvoie.

## Roadmap

- [x] v0.1 — calendrier, timeline, détail, recherche, archive, DMG signé
- [ ] Mises à jour Sparkle
- [ ] Cible CLI réutilisant LookiKit
- [ ] Index local pour recherche hors ligne

## Licence

MIT.
```

Add a `LICENSE` file (MIT, copyright 2026 Vincent Lauriat).

- [ ] **Step 3: Dry run, then real release**

```bash
SKIP_NOTARIZE=1 ./Scripts/release.sh 0.1.0
```

Expected: `release/LookiMac-0.1.0.dmg` exists, script prints the "signé mais NON notarisé" warning. Then, **only after Vincent confirms** (releases and tags need his go):

```bash
./Scripts/release.sh 0.1.0
spctl -a -t exec -vv build/Build/Products/Release/LookiMac.app   # accepted, source=Notarized Developer ID
xcrun stapler validate release/LookiMac-0.1.0.dmg                # The validate action worked!
```

- [ ] **Step 4: Commit**

```bash
git add Scripts README.md LICENSE
git commit -m "chore: add release script, README and license"
```

Tagging (`v0.1.0`) and the GitHub release are done with the `release` skill once Vincent asks; the branch `feat/v1` is merged into `main` by Vincent, never pushed directly.

---

## Self-review against the spec

| Spec section | Task |
|---|---|
| 1 Goal: review a day / find a memory / archive | 9–11 / 12 / 13 |
| 2 macOS 26, SwiftUI, xcodegen, name, bundle id | 7 |
| 2 Light cache, no DB | 5, 9, 10 |
| 2 Keychain only, optional import from credentials.json | 7, 8 |
| 2 Signed + notarized DMG, `release/` | 14 |
| 3 API surface: `/me`, `/moments?on_date`, `/moments/{id}`, search `page`/`page_size`, envelope, 422/429 | 2, 3 |
| 3 `location` as JSON string, only `cover_file` per moment | 2, 6 |
| 4.1 LookiClient, models, MomentCache (no signed URLs), JournalRenderer, DayArchiver (AsyncStream, skip existing) | 3, 2, 5, 4, 6 |
| 4.2 Sidebar calendar with marks, timeline, detail with AVPlayer, toolbar search + archive + open folder, Settings (key, test, folder, purge, import) | 9, 10, 11, 12, 13, 8 |
| 5 No key → settings on launch; bad key banner; 429 retry then message; network down → cached day + banner; empty day; expired URL re-fetch once; archive folder unavailable → ask again | 9 (RootView task + banner), 3 + 9, 9, 10, 11, 13 (`archiveSelectedDay` guard) |
| 6 Tests: fixtures, URLProtocol stub, golden journal, archiver on temp dir, `xcodebuild` after each change | 2–6, every app task |
| 7 release.sh from HealthCheck/template without Sparkle, `.gitignore`, feature branches | 14, 1 |

Type consistency checked: `DayKey.string/pathComponents/date(in:)`, `Moment.timeZone/duration/strippingSignedURLs()`, `Location.shortLabel`, `LookiError.userMessage`, `MomentCache.day/store/fetchedDays/thumbnail/storeThumbnail/purge/sizeOnDisk`, `DayArchiver.folder(for:in:)/fileName(for:)/archive(day:moments:into:)`, `ArchiveEvent` cases, `AppModel.select(day:)/reloadSelectedDay(force:)/showMonth/refreshMonthMarks/freshMoment(id:)/runSearch/loadMoreSearch/clearSearch/archiveSelectedDay/cancelArchive/dismissArchiveProgress/archivedFolder(for:)/openArchiveRoot/reveal` are used with the same names and signatures in every task that references them.
