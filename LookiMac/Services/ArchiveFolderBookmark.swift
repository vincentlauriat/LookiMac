import Foundation

/// Persists the user-chosen archive folder as a security-scoped bookmark (sandbox).
enum ArchiveFolderBookmark {
    private static let key = "archiveRootBookmark"

    static func save(_ url: URL) throws {
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale { try? save(url) }
        return url
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    /// Runs `body` while the security scope is open.
    static func withAccess<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }
}
