import Testing
import Foundation
@testable import LookiKit

@Suite struct JournalModelsTests {
    func page() throws -> JournalPage {
        try #require(try LookiJSON.decoder().decode(Envelope<JournalPage>.self, from: Fixture.data("journals")).data)
    }

    @Test func decodesFeedShape() throws {
        let p = try page()
        #expect(p.items.count == 2)
        #expect(p.items[0].date == DayKey(year: 2026, month: 9, day: 5))
        #expect(p.nextCursorId == "2026-09-04")
        #expect(p.hasMore == false)
        #expect(p.items[0].journals.count == 3)
        #expect(p.items[1].journals.count == 4)
    }

    @Test func decodesAllKnownTypesAndUnknown() throws {
        let all = try page().items.flatMap(\.journals)
        let types = all.map(\.type)
        #expect(types.contains(.diary)); #expect(types.contains(.comicPage)); #expect(types.contains(.dailyVlog))
        #expect(types.contains(.dailyHealthReport)); #expect(types.contains(.yesterdayRecap)); #expect(types.contains(.systemPost))
        #expect(types.contains(.unknown("FUTURE_TYPE")))
        #expect(JournalType.unknown("FUTURE_TYPE").rawValue == "FUTURE_TYPE")
        #expect(JournalType.unknown("FUTURE_TYPE").label == "FUTURE_TYPE")
        #expect(JournalType.comicPage.label == "BD")
        #expect(JournalType.dailyVlog.fileStem == "daily_vlog")
        #expect(JournalType.systemPost.isSystem)
        #expect(!JournalType.diary.isSystem)
    }

    @Test func decodesOptionalFieldsAndMedia() throws {
        let all = try page().items.flatMap(\.journals)
        let diary = try #require(all.first { $0.type == .diary })
        #expect(diary.title == nil); #expect(diary.content == nil); #expect(diary.startDate == nil)
        #expect(diary.headline == "Tech et café en ville.")
        #expect(diary.primaryMedia?.source.mediaType == .image)
        let comic = try #require(all.first { $0.type == .comicPage })
        #expect(comic.startDate == DayKey(year: 2026, month: 9, day: 4))
        #expect(comic.headline == "Une journée bien remplie")
        let vlog = try #require(all.first { $0.type == .dailyVlog })
        #expect(vlog.primaryMedia?.source.mediaType == .video)
        #expect(vlog.primaryMedia?.source.metadata?.durationMs == 54272)
        #expect(vlog.primaryMedia?.thumbnail?.mediaType == .image)
        let recap = try #require(all.first { $0.type == .yesterdayRecap })
        #expect(recap.content?.hasPrefix("### Exploration") == true)
        #expect(recap.mediaItems.isEmpty); #expect(recap.primaryMedia == nil)
        #expect(recap.timeZone.secondsFromGMT() == 7200)
    }

    @Test func roundTripsAndStripsSignedURLs() throws {
        let vlog = try #require(try page().items.flatMap(\.journals).first { $0.type == .dailyVlog })
        let stripped = vlog.strippingSignedURLs()
        #expect(stripped.mediaItems[0].source.temporaryURL == nil)
        #expect(stripped.mediaItems[0].thumbnail?.temporaryURL == nil)
        let data = try LookiJSON.encoder().encode(stripped)
        #expect(!String(decoding: data, as: UTF8.self).contains("SIGNED"))
        let back = try LookiJSON.decoder().decode(JournalPost.self, from: data)
        #expect(back == stripped)
        let unknown = try #require(try page().items.flatMap(\.journals).first { $0.type == .unknown("FUTURE_TYPE") })
        let back2 = try LookiJSON.decoder().decode(JournalPost.self, from: LookiJSON.encoder().encode(unknown))
        #expect(back2.type == .unknown("FUTURE_TYPE"))
    }
}
