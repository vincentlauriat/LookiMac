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
