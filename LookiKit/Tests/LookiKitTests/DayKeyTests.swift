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
        #expect(DayKey(string: "2026-02-30") == nil)
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
