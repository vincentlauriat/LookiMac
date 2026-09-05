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
