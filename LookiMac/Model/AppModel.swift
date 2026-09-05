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

    // MARK: Archive folder, connection test, cache

    private(set) var archiveRoot: URL? = ArchiveFolderBookmark.load()
    private(set) var cacheSize: Int64 = 0

    func chooseArchiveFolder(_ url: URL) throws {
        try ArchiveFolderBookmark.save(url)
        archiveRoot = url
    }

    func testConnection() async -> Result<UserProfile, LookiError> {
        guard let client else { return .failure(.missingAPIKey) }
        do { return .success(try await client.me()) }
        catch let e as LookiError { return .failure(e) }
        catch { return .failure(.network(error.localizedDescription)) }
    }

    func refreshCacheSize() async {
        cacheSize = await cache.sizeOnDisk()
    }

    func purgeCache() async throws {
        try await cache.purge()
        await refreshCacheSize()
    }
}
