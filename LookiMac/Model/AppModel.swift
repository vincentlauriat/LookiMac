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
}
