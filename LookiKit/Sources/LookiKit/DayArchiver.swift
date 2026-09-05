import Foundation

public protocol MediaDownloader: Sendable {
    /// Downloads `url` to `destination`, creating parent folders. Must be atomic (temp file + move).
    func download(_ url: URL, to destination: URL) async throws
}

public struct URLSessionDownloader: MediaDownloader {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func download(_ url: URL, to destination: URL) async throws {
        let (tmp, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: tmp)
            throw LookiError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path()) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: tmp, to: destination)
    }
}

public enum ArchiveEvent: Sendable, Equatable {
    case started(total: Int)
    case downloaded(momentID: String, fileName: String)
    case skipped(momentID: String, reason: String)
    case wroteJournal(URL)
    case finished(folder: URL)
}

/// Archives one day: `<root>/YYYY/MM/DD/{HHmm-<id8>.<ext>, journal.md, moments.json}`.
/// Cover media is downloaded through a fresh `GET /moments/{id}` so signed URLs are valid.
public struct DayArchiver: Sendable {
    public typealias DetailFetcher = @Sendable (String) async throws -> Moment

    public typealias JournalFetcher = @Sendable (String) async throws -> JournalPost

    private let fetchDetail: DetailFetcher
    private let fetchJournalDetail: JournalFetcher
    private let downloader: MediaDownloader

    public init(fetchDetail: @escaping DetailFetcher,
                fetchJournalDetail: @escaping JournalFetcher = { _ in throw LookiError.api(code: 0, detail: "no journal fetcher") },
                downloader: MediaDownloader) {
        self.fetchDetail = fetchDetail
        self.fetchJournalDetail = fetchJournalDetail
        self.downloader = downloader
    }

    public init(client: LookiClient, downloader: MediaDownloader = URLSessionDownloader()) {
        self.init(fetchDetail: { id in try await client.moment(id: id) },
                  fetchJournalDetail: { id in try await client.journal(id: id) },
                  downloader: downloader)
    }

    public static func journalFileName(for post: JournalPost) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = post.timeZone; f.dateFormat = "HHmm"
        let ext = post.primaryMedia?.source.mediaType.fileExtension ?? "bin"
        return "\(post.type.fileStem)-\(f.string(from: post.recordedAt))-\(post.id.prefix(8)).\(ext)"
    }

    public static func folder(for day: DayKey, in root: URL) -> URL {
        day.pathComponents.reduce(root) { $0.appending(path: $1) }
    }

    public static func fileName(for moment: Moment) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = moment.timeZone; f.dateFormat = "HHmm"
        let ext = moment.coverFile?.file.mediaType.fileExtension ?? "bin"
        return "\(f.string(from: moment.startTime))-\(moment.id.prefix(8)).\(ext)"
    }

    public func archive(day: DayKey, moments input: [Moment], journals: [JournalPost] = [], into root: URL) -> AsyncThrowingStream<ArchiveEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let fm = FileManager.default
                    let moments = input.sorted { $0.startTime < $1.startTime }
                    let posts = journals.filter { !$0.type.isSystem }.sorted { $0.recordedAt < $1.recordedAt }
                    let folder = Self.folder(for: day, in: root)
                    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                    continuation.yield(.started(total: moments.count + posts.count))

                    for m in moments {
                        try Task.checkCancellation()
                        guard m.coverFile != nil else {
                            continuation.yield(.skipped(momentID: m.id, reason: "aucun média")); continue
                        }
                        let name = Self.fileName(for: m)
                        let dest = folder.appending(path: name)
                        if let size = try? fm.attributesOfItem(atPath: dest.path())[.size] as? Int, size > 0 {
                            continuation.yield(.skipped(momentID: m.id, reason: "déjà archivé")); continue
                        }
                        do {
                            let fresh = try await fetchDetail(m.id)
                            guard let url = fresh.coverFile?.file.temporaryURL else {
                                continuation.yield(.skipped(momentID: m.id, reason: "URL absente")); continue
                            }
                            try await downloader.download(url, to: dest)
                            continuation.yield(.downloaded(momentID: m.id, fileName: name))
                        } catch let e as LookiError {
                            continuation.yield(.skipped(momentID: m.id, reason: e.userMessage))
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            continuation.yield(.skipped(momentID: m.id, reason: error.localizedDescription))
                        }
                    }

                    if !posts.isEmpty {
                        let sub = folder.appending(path: "journal")
                        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
                        for p in posts {
                            try Task.checkCancellation()
                            guard p.primaryMedia != nil else {
                                continuation.yield(.skipped(momentID: p.id, reason: "aucun média")); continue
                            }
                            let name = Self.journalFileName(for: p)
                            let dest = sub.appending(path: name)
                            if let size = try? fm.attributesOfItem(atPath: dest.path())[.size] as? Int, size > 0 {
                                continuation.yield(.skipped(momentID: p.id, reason: "déjà archivé")); continue
                            }
                            do {
                                let fresh = try await fetchJournalDetail(p.id)
                                guard let url = fresh.primaryMedia?.source.temporaryURL else {
                                    continuation.yield(.skipped(momentID: p.id, reason: "URL absente")); continue
                                }
                                try await downloader.download(url, to: dest)
                                continuation.yield(.downloaded(momentID: p.id, fileName: "journal/\(name)"))
                            } catch let e as LookiError {
                                continuation.yield(.skipped(momentID: p.id, reason: e.userMessage))
                            } catch is CancellationError {
                                throw CancellationError()
                            } catch {
                                continuation.yield(.skipped(momentID: p.id, reason: error.localizedDescription))
                            }
                        }
                        let json = try LookiJSON.encoder().encode(posts.map { $0.strippingSignedURLs() })
                        try json.write(to: folder.appending(path: "journals.json"), options: .atomic)
                    }

                    let journalURL = folder.appending(path: "journal.md")
                    let markdown = JournalRenderer.render(day: day, moments: moments, journals: posts, generatedAt: Date())
                    try markdown.write(to: journalURL, atomically: true, encoding: .utf8)
                    continuation.yield(.wroteJournal(journalURL))

                    let json = try LookiJSON.encoder().encode(moments.map { $0.strippingSignedURLs() })
                    try json.write(to: folder.appending(path: "moments.json"), options: .atomic)

                    continuation.yield(.finished(folder: folder))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
