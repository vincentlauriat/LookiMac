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
