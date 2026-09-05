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
