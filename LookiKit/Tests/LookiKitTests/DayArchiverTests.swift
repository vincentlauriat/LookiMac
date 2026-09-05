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
        #expect(events.contains(.downloaded(momentID: moments[0].id, fileName: "0959-aaaaaaaa/0959-aaaaaaaa.mp4")))
        #expect(events.contains(.downloaded(momentID: moments[1].id, fileName: "1235-aaaaaaaa/1235-aaaaaaaa.jpg")))
        #expect(events.last == .finished(folder: folder))

        // The video was fetched through the FRESH detail URL, not the stale list URL.
        let body = try String(contentsOf: folder.appending(path: "0959-aaaaaaaa/0959-aaaaaaaa.mp4"), encoding: .utf8)
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
        let folder = DayArchiver.folder(for: moments[0].date, in: root).appending(path: "0959-aaaaaaaa")
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
        #expect(events.contains(.downloaded(momentID: moments[1].id, fileName: "1235-aaaaaaaa/1235-aaaaaaaa.jpg")))
    }

    @Test func downloadsEveryClipIntoTheMomentFolder() async throws {
        let root = try tempRoot()
        let moments = try fixtureMoments()
        let p1 = try #require(try LookiJSON.decoder().decode(Envelope<FilesPage>.self, from: Fixture.data("moment-files")).data)
        let p2 = try #require(try LookiJSON.decoder().decode(Envelope<FilesPage>.self, from: Fixture.data("moment-files-2")).data)
        let clips = p1.items + p2.items
        let archiver = DayArchiver(
            fetchDetail: { id in moments.first { $0.id == id }! },
            fetchFiles: { id in id == moments[0].id ? clips : [] },
            downloader: FakeDownloader()
        )
        let events = try await collect(archiver.archive(day: moments[0].date, moments: moments, into: root))
        let day = root.appending(path: "2026/09/05")
        #expect(events.first == .started(total: 2))
        #expect(events.contains(.expanded(additional: 2)))          // 3 clips → 2 more than the moment itself
        #expect(events.contains(.downloaded(momentID: moments[0].id, fileName: "0959-aaaaaaaa/001-f1000000.mp4")))
        #expect(events.contains(.downloaded(momentID: moments[0].id, fileName: "0959-aaaaaaaa/002-f1000000.mp4")))
        #expect(events.contains(.downloaded(momentID: moments[0].id, fileName: "0959-aaaaaaaa/003-f1000000.jpg")))
        let files = try FileManager.default.contentsOfDirectory(atPath: day.appending(path: "0959-aaaaaaaa").path())
        #expect(Set(files) == ["001-f1000000.mp4", "002-f1000000.mp4", "003-f1000000.jpg"])
        #expect(try String(contentsOf: day.appending(path: "0959-aaaaaaaa/001-f1000000.mp4"), encoding: .utf8).contains("CLIP1"))
        // Second moment had no clip listing → cover fallback in its own folder.
        #expect(events.contains(.downloaded(momentID: moments[1].id, fileName: "1235-aaaaaaaa/1235-aaaaaaaa.jpg")))
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
    @Test func archivesJournalMediaAndJson() async throws {
        let root = try tempRoot()
        let moments = try fixtureMoments()
        let days = try #require(try LookiJSON.decoder().decode(Envelope<JournalPage>.self, from: Fixture.data("journals")).data).items
        let posts = days[1].journals    // comic(image), vlog(video+thumb), health(none), system(image)
        let day = DayKey(year: 2026, month: 9, day: 4)
        let archiver = DayArchiver(
            fetchDetail: { id in moments.first { $0.id == id }! },
            fetchJournalDetail: { id in posts.first { $0.id == id }! },
            downloader: FakeDownloader()
        )
        let events = try await collect(archiver.archive(day: day, moments: [], journals: posts, into: root))
        let folder = root.appending(path: "2026/09/04/journal")
        #expect(DayArchiver.journalFileName(for: posts[0]) == "comic_page-2345-j0000000.jpg")
        #expect(DayArchiver.journalFileName(for: posts[1]) == "daily_vlog-2340-j0000000.mp4")
        #expect(events.contains(.downloaded(momentID: posts[0].id, fileName: "journal/comic_page-2345-j0000000.jpg")))
        #expect(events.contains(.downloaded(momentID: posts[1].id, fileName: "journal/daily_vlog-2340-j0000000.mp4")))
        #expect(events.contains(.skipped(momentID: posts[2].id, reason: "aucun média")))
        #expect(!events.contains { if case .downloaded(let id, _) = $0 { return id == posts[3].id } else { return false } })
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path())
        #expect(Set(files) == ["comic_page-2345-j0000000.jpg", "daily_vlog-2340-j0000000.mp4"])
        let raw = try Data(contentsOf: root.appending(path: "2026/09/04/journals.json"))
        let back = try LookiJSON.decoder().decode([JournalPost].self, from: raw)
        #expect(back.count == 3)
        #expect(back.allSatisfy { $0.mediaItems.allSatisfy { $0.source.temporaryURL == nil } })
        let journal = try String(contentsOf: root.appending(path: "2026/09/04/journal.md"), encoding: .utf8)
        #expect(journal.contains("## Journal Looki"))
        #expect(events.first == .started(total: 3))
    }
}

actor Counter {
    var value = 0
    func increment() { value += 1 }
}
