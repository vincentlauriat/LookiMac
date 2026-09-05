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
