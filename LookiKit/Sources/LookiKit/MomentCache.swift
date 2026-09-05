import Foundation

public struct DayRecord: Codable, Sendable, Equatable {
    public let fetchedAt: Date
    public let moments: [Moment]
}

/// Disk cache of moment metadata (one JSON per day) and thumbnails (one file per cover id).
/// Signed URLs are stripped before writing. Everything lives under `root` and can be purged.
public actor MomentCache {
    public enum CacheError: Error, Equatable { case invalidIdentifier }

    private let root: URL
    private let fm = FileManager.default
    private let encoder = LookiJSON.encoder()
    private let decoder = LookiJSON.decoder()

    public init(root: URL) { self.root = root }

    public static func defaultRoot() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appending(path: "fr.lauriat.lookimac")
    }

    private var daysDir: URL { root.appending(path: "days") }
    private var thumbsDir: URL { root.appending(path: "thumbs") }
    private var journalsDir: URL { root.appending(path: "journals") }

    // MARK: Days

    public func day(_ key: DayKey) -> DayRecord? {
        guard let data = try? Data(contentsOf: daysDir.appending(path: "\(key.string).json")) else { return nil }
        return try? decoder.decode(DayRecord.self, from: data)
    }

    public func store(_ moments: [Moment], for key: DayKey) throws {
        try fm.createDirectory(at: daysDir, withIntermediateDirectories: true)
        let record = DayRecord(fetchedAt: Date(), moments: moments.map { $0.strippingSignedURLs() })
        try encoder.encode(record).write(to: daysDir.appending(path: "\(key.string).json"), options: .atomic)
    }

    /// Every fetched day of the month, with its moment count (0 for empty days).
    public func fetchedDays(year: Int, month: Int) -> [DayKey: Int] {
        let prefix = String(format: "%04d-%02d-", year, month)
        guard let names = try? fm.contentsOfDirectory(atPath: daysDir.path()) else { return [:] }
        var result: [DayKey: Int] = [:]
        for name in names where name.hasPrefix(prefix) && name.hasSuffix(".json") {
            guard let key = DayKey(string: String(name.dropLast(5))), let record = day(key) else { continue }
            result[key] = record.moments.count
        }
        return result
    }

    // MARK: Thumbnails

    public func thumbnail(for fileID: String) -> Data? {
        guard Self.isSafe(fileID) else { return nil }
        return try? Data(contentsOf: thumbsDir.appending(path: "\(fileID).jpg"))
    }

    public func storeThumbnail(_ data: Data, for fileID: String) throws {
        guard Self.isSafe(fileID) else { throw CacheError.invalidIdentifier }
        try fm.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
        try data.write(to: thumbsDir.appending(path: "\(fileID).jpg"), options: .atomic)
    }

    // MARK: Journals

    public func journals(for key: DayKey) -> [JournalPost]? {
        guard let data = try? Data(contentsOf: journalsDir.appending(path: "\(key.string).json")) else { return nil }
        return try? decoder.decode([JournalPost].self, from: data)
    }

    public func storeJournals(_ posts: [JournalPost], for key: DayKey) throws {
        try fm.createDirectory(at: journalsDir, withIntermediateDirectories: true)
        let stripped = posts.map { $0.strippingSignedURLs() }
        try encoder.encode(stripped).write(to: journalsDir.appending(path: "\(key.string).json"), options: .atomic)
    }

    /// Every cached journal day, newest first.
    public func journalDays() -> [DayKey] {
        guard let names = try? fm.contentsOfDirectory(atPath: journalsDir.path()) else { return [] }
        return names.filter { $0.hasSuffix(".json") }.compactMap { DayKey(string: String($0.dropLast(5))) }.sorted(by: >)
    }

    // MARK: Maintenance

    public func purge() throws {
        for dir in [daysDir, thumbsDir, journalsDir] where fm.fileExists(atPath: dir.path()) {
            try fm.removeItem(at: dir)
        }
    }

    public func sizeOnDisk() -> Int64 {
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    /// Identifiers become file names: only alphanumerics, dashes and underscores allowed.
    static func isSafe(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}
