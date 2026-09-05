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

    @Test func journalsFirstPageSendsMaxDaysOnly() async throws {
        let client = makeClient()
        StubURLProtocol.enqueue(path: "/api/v1/journals", body: try Fixture.data("journals"))
        let page = try await client.journals()
        #expect(page.items.count == 2)
        let url = try #require(StubURLProtocol.requests.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items == [URLQueryItem(name: "max_days", value: "31")])
    }

    @Test func journalsNextPageSendsCursorDate() async throws {
        let client = makeClient()
        StubURLProtocol.enqueue(path: "/api/v1/journals", body: try Fixture.data("journals"))
        _ = try await client.journals(cursorDate: "2026-09-04", maxDays: 7)
        let url = try #require(StubURLProtocol.requests.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "cursor_date", value: "2026-09-04")))
        #expect(items.contains(URLQueryItem(name: "max_days", value: "7")))
        #expect(!items.contains { $0.name == "cursor_id" })
    }

    @Test func momentFilesPagesThroughAllClips() async throws {
        let client = makeClient()
        StubURLProtocol.enqueue(path: "/api/v1/moments/m1/files", body: try Fixture.data("moment-files"))
        StubURLProtocol.enqueue(path: "/api/v1/moments/m1/files", body: try Fixture.data("moment-files-2"))
        let files = try await client.allMomentFiles(id: "m1")
        #expect(files.map(\.id) == ["f10000000000000000000001", "f10000000000000000000002", "f10000000000000000000003"])
        #expect(files[0].thumbnail?.mediaType == .image)
        #expect(files[1].thumbnail == nil)
        #expect(StubURLProtocol.requests.count == 2)
        let second = URLComponents(url: StubURLProtocol.requests[1].url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(second.contains(URLQueryItem(name: "cursor_id", value: "f10000000000000000000002")))
        #expect(second.contains(URLQueryItem(name: "limit", value: "100")))
    }

    @Test func momentFilesHighlightParam() async throws {
        let client = makeClient()
        StubURLProtocol.enqueue(path: "/api/v1/moments/m1/files", body: try Fixture.data("moment-files-2"))
        _ = try await client.momentFiles(id: "m1", highlight: true, limit: 20)
        let items = URLComponents(url: StubURLProtocol.requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "highlight", value: "true")))
        #expect(items.contains(URLQueryItem(name: "limit", value: "20")))
    }

    @Test func momentCalendarDecodesHighlights() async throws {
        let client = makeClient()
        StubURLProtocol.enqueue(path: "/api/v1/moments/calendar", body: try Fixture.data("moments-calendar"))
        let days = try await client.momentCalendar(start: DayKey(year: 2026, month: 9, day: 1), end: DayKey(year: 2026, month: 9, day: 30))
        #expect(days.map(\.date.string) == ["2026-09-04", "2026-09-05"])
        #expect(days[0].highlightMoment?.title == "Lunettes connectées à l'IFA")
        #expect(days[1].highlightMoment == nil)
        let items = URLComponents(url: StubURLProtocol.requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "start_date", value: "2026-09-01")))
        #expect(items.contains(URLQueryItem(name: "end_date", value: "2026-09-30")))
    }

    @Test func journalCalendarDecodes() async throws {
        let client = makeClient()
        StubURLProtocol.enqueue(path: "/api/v1/journals/calendar", body: try Fixture.data("journals-calendar"))
        let days = try await client.journalCalendar(start: DayKey(year: 2026, month: 9, day: 1), end: DayKey(year: 2026, month: 9, day: 30))
        #expect(days.map(\.date.string) == ["2026-09-04", "2026-09-05"])
    }

    @Test func journalDetail() async throws {
        let client = makeClient()
        let page = try #require(try LookiJSON.decoder().decode(Envelope<JournalPage>.self, from: Fixture.data("journals")).data)
        let post = page.items[0].journals[0]
        let body = try JSONSerialization.data(withJSONObject: ["code": 0, "detail": "OK", "data": try JSONSerialization.jsonObject(with: LookiJSON.encoder().encode(post))])
        StubURLProtocol.enqueue(path: "/api/v1/journals/\(post.id)", body: body)
        let fetched = try await client.journal(id: post.id)
        #expect(fetched.id == post.id)
        #expect(fetched.type == .diary)
    }
}
