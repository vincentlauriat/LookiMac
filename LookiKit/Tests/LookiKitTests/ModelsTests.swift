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
