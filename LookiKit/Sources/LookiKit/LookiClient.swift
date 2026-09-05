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

    /// Journal feed, newest day first. Pass `nextCursorId` (a date) from the previous page as `cursorDate`.
    public func journals(cursorDate: String? = nil, maxDays: Int = 31) async throws -> JournalPage {
        var query = [URLQueryItem(name: "max_days", value: String(min(max(maxDays, 1), 31)))]
        if let cursorDate { query.append(URLQueryItem(name: "cursor_date", value: cursorDate)) }
        return try await get("journals", query: query, as: JournalPage.self)
    }

    /// Days that have journal posts in the range (inclusive).
    public func journalCalendar(start: DayKey, end: DayKey) async throws -> [JournalCalendarDay] {
        try await get("journals/calendar", query: [
            URLQueryItem(name: "start_date", value: start.string),
            URLQueryItem(name: "end_date", value: end.string),
        ], as: [JournalCalendarDay].self)
    }

    /// Days that have moments in the range (inclusive), each with its highlight moment.
    public func momentCalendar(start: DayKey, end: DayKey) async throws -> [CalendarDay] {
        try await get("moments/calendar", query: [
            URLQueryItem(name: "start_date", value: start.string),
            URLQueryItem(name: "end_date", value: end.string),
        ], as: [CalendarDay].self)
    }

    /// One page of the clips (photos/videos) of a moment.
    public func momentFiles(id: String, highlight: Bool? = nil, cursor: String? = nil, limit: Int = 100) async throws -> FilesPage {
        var query = [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 100)))]
        if let highlight { query.append(URLQueryItem(name: "highlight", value: highlight ? "true" : "false")) }
        if let cursor { query.append(URLQueryItem(name: "cursor_id", value: cursor)) }
        return try await get("moments/\(id)/files", query: query, as: FilesPage.self)
    }

    /// Every clip of a moment, following the cursor (at most 10 pages of 100).
    public func allMomentFiles(id: String, highlight: Bool? = nil) async throws -> [MomentFile] {
        var all: [MomentFile] = []
        var cursor: String? = nil
        for _ in 0..<10 {
            let page = try await momentFiles(id: id, highlight: highlight, cursor: cursor)
            all += page.items
            guard page.hasMore, let next = page.nextCursorId, next != cursor else { break }
            cursor = next
        }
        return all.sorted { $0.createdAt < $1.createdAt }
    }

    public func journal(id: String) async throws -> JournalPost {
        try await get("journals/\(id)", as: JournalPost.self)
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
