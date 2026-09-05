import AppKit
import Foundation
import Observation
import LookiKit

@MainActor
@Observable
final class AppModel {
    // MARK: Credentials

    private(set) var apiKey: String?
    private(set) var client: LookiClient?
    let cache: MomentCache
    private(set) var thumbnails: ThumbnailLoader

    var needsSetup: Bool { client == nil }

    init(cache: MomentCache = MomentCache(root: MomentCache.defaultRoot())) {
        self.cache = cache
        var client: LookiClient?
        if let key = try? KeychainStore.readAPIKey(), !key.isEmpty {
            apiKey = key
            client = LookiClient(apiKey: key)
        }
        self.client = client
        thumbnails = Self.makeThumbnailLoader(cache: cache, client: client)
    }

    private static func makeThumbnailLoader(cache: MomentCache, client: LookiClient?) -> ThumbnailLoader {
        ThumbnailLoader(cache: cache, freshMoment: { id in
            guard let client else { throw LookiError.missingAPIKey }
            return try await client.moment(id: id)
        }, freshPost: { id in
            guard let client else { throw LookiError.missingAPIKey }
            return try await client.journal(id: id)
        })
    }

    func setAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try KeychainStore.saveAPIKey(trimmed)
        apiKey = trimmed
        client = LookiClient(apiKey: trimmed)
        thumbnails = Self.makeThumbnailLoader(cache: cache, client: client)
    }

    func clearAPIKey() throws {
        try KeychainStore.deleteAPIKey()
        apiKey = nil
        client = nil
        thumbnails = Self.makeThumbnailLoader(cache: cache, client: nil)
    }

    func freshMoment(id: String) async throws -> Moment {
        guard let client else { throw LookiError.missingAPIKey }
        return try await client.moment(id: id)
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

    // MARK: Day selection and loading

    var localTimeZone: TimeZone { TimeZone.current }
    static func today(in tz: TimeZone) -> DayKey { DayKey(date: Date(), timeZone: tz) }

    var selectedDay: DayKey = AppModel.today(in: .current)
    private(set) var dayState: DayState = .idle
    private(set) var visibleMonth: (year: Int, month: Int) = (AppModel.today(in: .current).year, AppModel.today(in: .current).month)
    private(set) var monthMarks: [DayKey: Int] = [:]
    var selectedMoment: Moment?
    var banner: Banner?

    private var dayLoadTask: Task<Void, Never>?
    private var monthTask: Task<Void, Never>?

    func select(day: DayKey) {
        guard day != selectedDay || dayState == .idle else { return }
        selectedDay = day
        selectedMoment = nil
        if (day.year, day.month) != visibleMonth { showMonth(year: day.year, month: day.month) }
        dayLoadTask?.cancel()
        dayLoadTask = Task { await reloadSelectedDay() }
    }

    /// Cache first, then network (unless the cached record is from today and `force` is false).
    func reloadSelectedDay(force: Bool = false) async {
        let day = selectedDay
        if !force, let cached = await cache.day(day) {
            apply(cached.moments, for: day)
            // A cached "today" may be incomplete: refresh silently in the background.
            if day != Self.today(in: localTimeZone) { return }
        } else {
            dayState = .loading
        }
        guard let client else { dayState = .failed(.missingAPIKey); return }
        do {
            let fresh = try await client.moments(on: day)
            guard !Task.isCancelled, day == selectedDay else { return }
            try? await cache.store(fresh, for: day)
            apply(fresh, for: day)
            monthMarks[day] = fresh.count
            banner = nil
        } catch let e as LookiError {
            guard day == selectedDay else { return }
            if case .loaded = dayState { banner = Banner(text: e.userMessage, isError: true, showsSettings: e == .unauthorized) }
            else { dayState = .failed(e) }
        } catch {
            if case .loaded = dayState {} else { dayState = .failed(.network(error.localizedDescription)) }
        }
    }

    private func apply(_ moments: [Moment], for day: DayKey) {
        guard day == selectedDay else { return }
        dayState = moments.isEmpty ? .empty : .loaded(moments.sorted { $0.startTime < $1.startTime })
    }

    func showMonth(year: Int, month: Int) {
        visibleMonth = (year, month)
        monthTask?.cancel()
        monthTask = Task { await refreshMonthMarks() }
    }

    /// Marks from the cache immediately; then fetches any day of the month not yet cached,
    /// oldest first, never beyond today, one request at a time.
    func refreshMonthMarks() async {
        let (year, month) = visibleMonth
        monthMarks = await cache.fetchedDays(year: year, month: month)
        guard let client else { return }
        let today = Self.today(in: localTimeZone)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = localTimeZone
        let first = DayKey(year: year, month: month, day: 1)
        let count = cal.range(of: .day, in: .month, for: first.date(in: localTimeZone))!.count
        for d in 1...count {
            let key = DayKey(year: year, month: month, day: d)
            if key > today || monthMarks[key] != nil { continue }
            if Task.isCancelled || visibleMonth != (year, month) { return }
            do {
                let moments = try await client.moments(on: key)
                try? await cache.store(moments, for: key)
                monthMarks[key] = moments.count
            } catch {
                return   // stop scanning on the first error; the day view reports it when selected
            }
        }
    }

    // MARK: Journal

    var sidebarMode: SidebarMode = SidebarMode(rawValue: UserDefaults.standard.string(forKey: "sidebarMode") ?? "") ?? .moments {
        didSet { UserDefaults.standard.set(sidebarMode.rawValue, forKey: "sidebarMode") }
    }
    var showSystemPosts: Bool = UserDefaults.standard.bool(forKey: "showSystemPosts") {
        didSet { UserDefaults.standard.set(showSystemPosts, forKey: "showSystemPosts") }
    }
    private(set) var journalDays: [JournalDay] = []
    private(set) var journalState: JournalState = .idle
    var selectedPost: JournalPost?

    var visibleJournalDays: [JournalDay] {
        journalDays.compactMap { day in
            let posts = showSystemPosts ? day.journals : day.journals.filter { !$0.type.isSystem }
            return posts.isEmpty ? nil : JournalDay(date: day.date, journals: posts.sorted { $0.recordedAt > $1.recordedAt })
        }
    }

    func hasJournal(for day: DayKey) -> Bool {
        journalDays.contains { $0.date == day && $0.journals.contains { !$0.type.isSystem } }
    }

    func freshJournal(id: String) async throws -> JournalPost {
        guard let client else { throw LookiError.missingAPIKey }
        return try await client.journal(id: id)
    }

    /// Cache first, then the whole feed from the API (follows has_more, max 20 pages, stops if the cursor is ignored).
    func loadJournal(force: Bool = false) async {
        if !force, journalDays.isEmpty {
            let cachedDays = await cache.journalDays()
            var days: [JournalDay] = []
            for d in cachedDays {
                if let posts = await cache.journals(for: d) { days.append(JournalDay(date: d, journals: posts)) }
            }
            if !days.isEmpty { journalDays = days; journalState = .loaded }
        }
        if journalDays.isEmpty { journalState = .loading }
        guard let client else { journalState = .failed(.missingAPIKey); return }
        do {
            var collected: [DayKey: [JournalPost]] = [:]
            var cursor: String? = nil
            var firstID: String? = nil
            for _ in 0..<20 {
                let page = try await client.journals(cursor: cursor)
                let pageFirst = page.items.first?.journals.first?.id
                if cursor != nil, pageFirst == firstID { break }          // API ignored the cursor
                if firstID == nil { firstID = pageFirst }
                for day in page.items { collected[day.date, default: []] += day.journals }
                guard page.hasMore, let next = page.nextCursorId, next != cursor else { break }
                cursor = next
            }
            guard !Task.isCancelled else { return }
            let merged = collected.keys.sorted(by: >).map { JournalDay(date: $0, journals: collected[$0]!) }
            for day in merged { try? await cache.storeJournals(day.journals, for: day.date) }
            journalDays = merged
            journalState = .loaded
        } catch let e as LookiError {
            if journalDays.isEmpty { journalState = .failed(e) }
            else { banner = Banner(text: e.userMessage, isError: true, showsSettings: e == .unauthorized) }
        } catch {
            if journalDays.isEmpty { journalState = .failed(.network(error.localizedDescription)) }
        }
    }

    // MARK: Search

    var searchQuery: String = ""
    private(set) var searchResults: [Moment] = []
    private(set) var searchHasMore = false
    private(set) var isSearching = false
    private(set) var searchError: LookiError?
    private var searchPage = 0
    private let searchPageSize = 20

    var isSearchMode: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Debounced by the caller (`.task(id:)` in the view); resets pagination.
    func runSearch() async {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { clearSearch(); return }
        guard let client else { searchError = .missingAPIKey; return }
        searchResults = []; searchPage = 0; searchHasMore = false; searchError = nil
        isSearching = true
        defer { isSearching = false }
        do {
            let page = try await client.search(query: q, page: 1, pageSize: searchPageSize)
            guard !Task.isCancelled, q == searchQuery.trimmingCharacters(in: .whitespaces) else { return }
            searchResults = page.items; searchHasMore = page.hasMore; searchPage = 1
        } catch let e as LookiError { searchError = e }
        catch { searchError = .network(error.localizedDescription) }
    }

    func loadMoreSearch() async {
        guard searchHasMore, !isSearching, let client else { return }
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        isSearching = true
        defer { isSearching = false }
        do {
            let page = try await client.search(query: q, page: searchPage + 1, pageSize: searchPageSize)
            guard q == searchQuery.trimmingCharacters(in: .whitespaces) else { return }
            let known = Set(searchResults.map(\.id))
            searchResults += page.items.filter { !known.contains($0.id) }
            searchHasMore = page.hasMore; searchPage += 1
        } catch let e as LookiError { searchError = e }
        catch { searchError = .network(error.localizedDescription) }
    }

    func clearSearch() {
        searchQuery = ""; searchResults = []; searchHasMore = false; searchError = nil; searchPage = 0
    }

    // MARK: Archive

    struct ArchiveProgress: Equatable {
        var total = 0
        var done = 0
        var skipped = 0
        var lastMessage = ""
        var folder: URL?
        var finished = false
        var error: String?
    }

    private(set) var archiveProgress: ArchiveProgress?
    private var archiveTask: Task<Void, Never>?
    var isArchiving: Bool { archiveProgress != nil && archiveProgress?.finished == false && archiveProgress?.error == nil }

    func archiveSelectedDay() {
        guard let client, let root = archiveRoot else {
            let text = archiveRoot == nil ? "Choisis d'abord un dossier d'archive dans les Réglages." : LookiError.missingAPIKey.userMessage
            banner = Banner(text: text, isError: true, showsSettings: true)
            return
        }
        let moments = dayState.moments
        let posts = journalDays.first { $0.date == selectedDay }?.journals ?? []
        let archivablePosts = posts.filter { !$0.type.isSystem }
        guard !moments.isEmpty || !archivablePosts.isEmpty else {
            banner = Banner(text: "Rien à archiver pour ce jour.", isError: false, showsSettings: false)
            return
        }
        let day = selectedDay
        archiveProgress = ArchiveProgress(total: moments.count + archivablePosts.count)
        archiveTask = Task {
            let archiver = DayArchiver(client: client)
            // Keep the security scope open for the whole run.
            let ok = root.startAccessingSecurityScopedResource()
            defer { if ok { root.stopAccessingSecurityScopedResource() } }
            do {
                for try await event in archiver.archive(day: day, moments: moments, journals: posts, into: root) {
                    switch event {
                    case .started(let total): archiveProgress?.total = total
                    case .downloaded(_, let name): archiveProgress?.done += 1; archiveProgress?.lastMessage = name
                    case .skipped(_, let reason): archiveProgress?.done += 1; archiveProgress?.skipped += 1; archiveProgress?.lastMessage = reason
                    case .wroteJournal: archiveProgress?.lastMessage = "journal.md"
                    case .finished(let folder): archiveProgress?.folder = folder; archiveProgress?.finished = true
                    }
                }
            } catch is CancellationError {
                archiveProgress = nil
            } catch {
                archiveProgress?.error = (error as? LookiError)?.userMessage ?? error.localizedDescription
            }
        }
    }

    func cancelArchive() { archiveTask?.cancel(); archiveProgress = nil }
    func dismissArchiveProgress() { archiveProgress = nil }

    func archivedFolder(for day: DayKey) -> URL? {
        guard let root = archiveRoot else { return nil }
        let folder = DayArchiver.folder(for: day, in: root)
        let exists = (try? ArchiveFolderBookmark.withAccess(root) { _ in
            FileManager.default.fileExists(atPath: folder.appending(path: "journal.md").path())
        }) ?? false
        return exists ? folder : nil
    }

    func openArchiveRoot() {
        guard let root = archiveRoot else { return }
        _ = try? ArchiveFolderBookmark.withAccess(root) { NSWorkspace.shared.open($0) }
    }

    func reveal(_ url: URL) {
        guard let root = archiveRoot else { return }
        _ = try? ArchiveFolderBookmark.withAccess(root) { _ in NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}
