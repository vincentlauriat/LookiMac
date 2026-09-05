import Testing
import Foundation
@testable import LookiKit

@Suite struct DayArchiverTests {
    /// Writes a marker body so the test can verify which URL landed where.
    struct FakeDownloader: MediaDownloader {
        func download(_ url: URL, to destination: URL) async throws {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(url.absoluteString.utf8).write(to: destination)
        }
    }

    func tempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "lookikit-archive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func fixtureMoments() throws -> [Moment] {
        try #require(try LookiJSON.decoder().decode(Envelope<[Moment]>.self, from: Fixture.data("moments-day")).data)
    }

    func collect(_ stream: AsyncThrowingStream<ArchiveEvent, Error>) async throws -> [ArchiveEvent] {
        var events: [ArchiveEvent] = []
        for try await e in stream { events.append(e) }
        return events
    }

    @Test func folderAndFileNaming() throws {
        let m = try fixtureMoments()[0]
        let root = URL(filePath: "/tmp/archive")
        #expect(DayArchiver.folder(for: m.date, in: root).path() == "/tmp/archive/2026/09/05")
        #expect(DayArchiver.fileName(for: m) == "0959-aaaaaaaa.mp4")
        #expect(DayArchiver.fileName(for: try fixtureMoments()[1]) == "1235-aaaaaaaa.jpg")
    }

    @Test func archivesADayUsingFreshDetailURLs() async throws {
        let root = try tempRoot()
        let moments = try fixtureMoments()
        let fresh = try #require(try LookiJSON.decoder().decode(Envelope<Moment>.self, from: Fixture.data("moment-detail")).data)
        let archiver = DayArchiver(
            fetchDetail: { id in id == fresh.id ? fresh : moments[1] },
            downloader: FakeDownloader()
        )
        let events = try await collect(archiver.archive(day: moments[0].date, moments: moments, into: root))
        let folder = root.appending(path: "2026/09/05")

        #expect(events.first == .started(total: 2))
        #expect(events.contains(.downloaded(momentID: moments[0].id, fileName: "0959-aaaaaaaa.mp4")))
        #expect(events.contains(.downloaded(momentID: moments[1].id, fileName: "1235-aaaaaaaa.jpg")))
        #expect(events.last == .finished(folder: folder))

        // The video was fetched through the FRESH detail URL, not the stale list URL.
        let body = try String(contentsOf: folder.appending(path: "0959-aaaaaaaa.mp4"), encoding: .utf8)
        #expect(body.contains("FRESH1"))

        let journal = try String(contentsOf: folder.appending(path: "journal.md"), encoding: .utf8)
        #expect(journal.hasPrefix("# Journal Looki — samedi 5 septembre 2026"))

        let raw = try Data(contentsOf: folder.appending(path: "moments.json"))
        let back = try LookiJSON.decoder().decode([Moment].self, from: raw)
        #expect(back.count == 2)
        #expect(back.allSatisfy { $0.coverFile?.file.temporaryURL == nil })
    }

    @Test func skipsExistingNonEmptyFiles() async throws {
        let root = try tempRoot()
        let moments = try fixtureMoments()
        let folder = DayArchiver.folder(for: moments[0].date, in: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("already".utf8).write(to: folder.appending(path: "0959-aaaaaaaa.mp4"))
        let counter = Counter()
        let archiver = DayArchiver(
            fetchDetail: { id in await counter.increment(); return moments.first { $0.id == id }! },
            downloader: FakeDownloader()
        )
        let events = try await collect(archiver.archive(day: moments[0].date, moments: moments, into: root))
        #expect(await counter.value == 1)   // only the second moment needed a fresh URL
        #expect(events.contains(.skipped(momentID: moments[0].id, reason: "déjà archivé")))
        #expect(try String(contentsOf: folder.appending(path: "0959-aaaaaaaa.mp4"), encoding: .utf8) == "already")
    }

    @Test func momentWithoutCoverIsSkippedNotFatal() async throws {
        let root = try tempRoot()
        var moments = try fixtureMoments()
        moments[0].coverFile = nil
        let snapshot = moments
        let archiver = DayArchiver(fetchDetail: { id in snapshot.first { $0.id == id }! }, downloader: FakeDownloader())
        let events = try await collect(archiver.archive(day: moments[0].date, moments: moments, into: root))
        #expect(events.contains(.skipped(momentID: moments[0].id, reason: "aucun média")))
        #expect(events.contains(.downloaded(momentID: moments[1].id, fileName: "1235-aaaaaaaa.jpg")))
    }

    @Test func detailFailureIsReportedAsSkippedAndArchiveContinues() async throws {
        let root = try tempRoot()
        let moments = try fixtureMoments()
        let archiver = DayArchiver(
            fetchDetail: { id in
                if id == moments[0].id { throw LookiError.api(code: 101, detail: "not found") }
                return moments[1]
            },
            downloader: FakeDownloader()
        )
        let events = try await collect(archiver.archive(day: moments[0].date, moments: moments, into: root))
        #expect(events.contains(.skipped(momentID: moments[0].id, reason: "Looki : not found")))
        #expect(events.last == .finished(folder: root.appending(path: "2026/09/05")))
    }
}

actor Counter {
    var value = 0
    func increment() { value += 1 }
}
