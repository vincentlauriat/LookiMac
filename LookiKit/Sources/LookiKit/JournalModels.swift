import Foundation

/// Kind of AI-generated post in the Looki journal feed. Unknown API values are preserved.
public enum JournalType: Hashable, Sendable, Codable {
    case diary, comicPage, dailyVlog, dailyHealthReport, yesterdayRecap, systemPost
    case unknown(String)

    private static let table: [(JournalType, String)] = [
        (.diary, "DIARY"), (.comicPage, "COMIC_PAGE"), (.dailyVlog, "DAILY_VLOG"),
        (.dailyHealthReport, "DAILY_HEALTH_REPORT"), (.yesterdayRecap, "YESTERDAY_RECAP"), (.systemPost, "SYSTEM_POST"),
    ]

    public init(rawValue: String) {
        self = Self.table.first { $0.1 == rawValue }?.0 ?? .unknown(rawValue)
    }

    public var rawValue: String {
        if case .unknown(let raw) = self { return raw }
        return Self.table.first { $0.0 == self }!.1
    }

    /// Short French badge label.
    public var label: String {
        switch self {
        case .diary: "Journal"
        case .comicPage: "BD"
        case .dailyVlog: "Vlog"
        case .dailyHealthReport: "Santé"
        case .yesterdayRecap: "Récap"
        case .systemPost: "Looki"
        case .unknown(let raw): raw
        }
    }

    /// Lowercase raw value, used in archive file names.
    public var fileStem: String { rawValue.lowercased() }

    /// Looki announcements rather than content derived from the user's day.
    public var isSystem: Bool { self == .systemPost }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

public struct JournalMedia: Codable, Sendable, Equatable, Hashable {
    public var source: RemoteFile
    public var thumbnail: RemoteFile?

    public init(source: RemoteFile, thumbnail: RemoteFile?) { self.source = source; self.thumbnail = thumbnail }
}

public struct JournalPost: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let type: JournalType
    public let title: String?
    public let description: String?
    /// Markdown body (headings, bullets, images). Present on recaps and system posts.
    public let content: String?
    public let startDate: DayKey?
    public var mediaItems: [JournalMedia]
    public let date: DayKey
    public let tz: String
    public let recordedAt: Date
    public let createdAt: Date

    public init(id: String, type: JournalType, title: String?, description: String?, content: String?, startDate: DayKey?, mediaItems: [JournalMedia], date: DayKey, tz: String, recordedAt: Date, createdAt: Date) {
        self.id = id; self.type = type; self.title = title; self.description = description; self.content = content
        self.startDate = startDate; self.mediaItems = mediaItems; self.date = date; self.tz = tz
        self.recordedAt = recordedAt; self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, type, title, description, content, startDate, mediaItems, date, tz, recordedAt, createdAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(JournalType.self, forKey: .type)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        content = try c.decodeIfPresent(String.self, forKey: .content)
        startDate = try c.decodeIfPresent(DayKey.self, forKey: .startDate)
        mediaItems = try c.decodeIfPresent([JournalMedia].self, forKey: .mediaItems) ?? []
        date = try c.decode(DayKey.self, forKey: .date)
        tz = try c.decodeIfPresent(String.self, forKey: .tz) ?? "+00:00"
        recordedAt = try c.decode(Date.self, forKey: .recordedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? recordedAt
    }

    public var timeZone: TimeZone { TimeZone.fromOffset(tz) ?? TimeZone(secondsFromGMT: 0)! }

    /// Title, else caption, else the type label — never empty.
    public var headline: String {
        if let title, !title.isEmpty { return title }
        if let description, !description.isEmpty { return description }
        return type.label
    }

    public var primaryMedia: JournalMedia? { mediaItems.first }

    /// Copy without any signed URL — the only form that may be written to disk.
    public func strippingSignedURLs() -> JournalPost {
        var copy = self
        copy.mediaItems = mediaItems.map { m in
            var m = m
            m.source.temporaryURL = nil
            m.thumbnail?.temporaryURL = nil
            return m
        }
        return copy
    }
}

public struct JournalDay: Codable, Sendable, Equatable {
    public let date: DayKey
    public var journals: [JournalPost]
    public init(date: DayKey, journals: [JournalPost]) { self.date = date; self.journals = journals }
}

public struct JournalPage: Decodable, Sendable {
    public let items: [JournalDay]
    public let nextCursorId: String?
    public let hasMore: Bool
}
