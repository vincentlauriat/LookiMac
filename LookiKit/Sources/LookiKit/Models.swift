import Foundation

/// Generic response envelope of the Looki Open API. `code == 0` means success.
/// `data` is decoded leniently: if it is absent, `null`, or not of type `T`
/// (error payloads put an `errors` object there), it becomes `nil`.
public struct Envelope<T: Decodable & Sendable>: Decodable, Sendable {
    public let code: Int
    public let detail: String
    public let data: T?

    public init(code: Int, detail: String, data: T?) {
        self.code = code; self.detail = detail; self.data = data
    }

    private enum CodingKeys: String, CodingKey { case code, detail, data }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(Int.self, forKey: .code)
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        if code == 0 {
            data = try c.decodeIfPresent(T.self, forKey: .data)
        } else {
            data = try? c.decodeIfPresent(T.self, forKey: .data)
        }
    }
}

public struct UserProfile: Codable, Sendable, Equatable {
    public let id: String
    public let firstName: String?
    public let lastName: String?
    public let tz: String?

    public var displayName: String {
        [firstName, lastName].compactMap { $0 }.joined(separator: " ")
    }
}

public struct UserEnvelope: Decodable, Sendable {
    public let user: UserProfile
}

public enum MediaType: String, Codable, Sendable, Hashable {
    case video = "VIDEO"
    case image = "IMAGE"
    case unknown = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MediaType(rawValue: raw) ?? .unknown
    }

    /// File extension used when archiving.
    public var fileExtension: String {
        switch self {
        case .video: "mp4"
        case .image: "jpg"
        case .unknown: "bin"
        }
    }
}

public struct FileMetadata: Codable, Sendable, Equatable, Hashable {
    public let width: Int?
    public let height: Int?
    public let durationMs: Int?
}

public struct RemoteFile: Codable, Sendable, Equatable, Hashable {
    /// Signed, expiring URL. `nil` once cached (see `Moment.strippingSignedURLs`).
    public var temporaryURL: URL?
    public let mediaType: MediaType
    public let metadata: FileMetadata?
    /// Size in bytes when the API provides it.
    public let size: Int?

    // With .convertFromSnakeCase, "temporary_url" arrives as "temporaryUrl".
    private enum CodingKeys: String, CodingKey { case temporaryURL = "temporaryUrl", mediaType, metadata, size }

    public init(temporaryURL: URL?, mediaType: MediaType, metadata: FileMetadata?, size: Int? = nil) {
        self.temporaryURL = temporaryURL; self.mediaType = mediaType; self.metadata = metadata; self.size = size
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Signed URLs contain characters URL(string:) may reject; be lenient.
        if let s = try c.decodeIfPresent(String.self, forKey: .temporaryURL), !s.isEmpty {
            temporaryURL = URL(string: s)
        } else {
            temporaryURL = nil
        }
        mediaType = try c.decodeIfPresent(MediaType.self, forKey: .mediaType) ?? .unknown
        metadata = try c.decodeIfPresent(FileMetadata.self, forKey: .metadata)
        size = try c.decodeIfPresent(Int.self, forKey: .size)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(temporaryURL?.absoluteString, forKey: .temporaryURL)
        try c.encode(mediaType, forKey: .mediaType)
        try c.encodeIfPresent(metadata, forKey: .metadata)
        try c.encodeIfPresent(size, forKey: .size)
    }
}

/// Reverse-geocoded place. The API ships it as a JSON **string** inside the file object.
public struct Location: Codable, Sendable, Equatable, Hashable {
    public let street: String?
    public let locality: String?
    public let administrativeArea: String?
    public let isoCountryCode: String?
    public let subLocality: String?

    public init(street: String?, locality: String?, administrativeArea: String?, isoCountryCode: String?, subLocality: String?) {
        self.street = street; self.locality = locality; self.administrativeArea = administrativeArea
        self.isoCountryCode = isoCountryCode; self.subLocality = subLocality
    }

    /// Street if known, else locality, else country code, else empty.
    public var shortLabel: String {
        street ?? locality ?? isoCountryCode ?? ""
    }

    static func parse(_ s: String?) -> Location? {
        guard let s, let data = s.data(using: .utf8) else { return nil }
        // Keys inside the string are camelCase already; use a plain decoder.
        return try? JSONDecoder().decode(Location.self, from: data)
    }
}

public struct MomentFile: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public var file: RemoteFile
    /// Small preview when the API provides one (clip listings); `nil` on cover files.
    public var thumbnail: RemoteFile?
    public let location: Location?
    public let createdAt: Date
    public let tz: String

    private enum CodingKeys: String, CodingKey { case id, file, thumbnail, location, createdAt, tz }

    public init(id: String, file: RemoteFile, thumbnail: RemoteFile? = nil, location: Location?, createdAt: Date, tz: String) {
        self.id = id; self.file = file; self.thumbnail = thumbnail; self.location = location; self.createdAt = createdAt; self.tz = tz
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        file = try c.decode(RemoteFile.self, forKey: .file)
        thumbnail = try c.decodeIfPresent(RemoteFile.self, forKey: .thumbnail)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        tz = try c.decodeIfPresent(String.self, forKey: .tz) ?? "+00:00"
        // Accept both the API form (string) and our own re-encoded form (object).
        if let obj = try? c.decodeIfPresent(Location.self, forKey: .location) {
            location = obj
        } else {
            location = Location.parse(try? c.decodeIfPresent(String.self, forKey: .location))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(file, forKey: .file)
        try c.encodeIfPresent(thumbnail, forKey: .thumbnail)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(tz, forKey: .tz)
    }
}

public struct Moment: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let description: String
    public let mediaTypes: [MediaType]
    public var coverFile: MomentFile?
    public let date: DayKey
    public let tz: String
    public let startTime: Date
    public let endTime: Date

    public init(id: String, title: String, description: String, mediaTypes: [MediaType], coverFile: MomentFile?, date: DayKey, tz: String, startTime: Date, endTime: Date) {
        self.id = id; self.title = title; self.description = description; self.mediaTypes = mediaTypes
        self.coverFile = coverFile; self.date = date; self.tz = tz; self.startTime = startTime; self.endTime = endTime
    }

    /// The moment's own offset (e.g. `+02:00`), falling back to UTC.
    public var timeZone: TimeZone { TimeZone.fromOffset(tz) ?? TimeZone(secondsFromGMT: 0)! }

    public var duration: TimeInterval { endTime.timeIntervalSince(startTime) }

    /// Copy without any signed URL — the only form that may be written to disk caches.
    public func strippingSignedURLs() -> Moment {
        var copy = self
        copy.coverFile?.file.temporaryURL = nil
        copy.coverFile?.thumbnail?.temporaryURL = nil
        return copy
    }
}

public struct SearchPage: Decodable, Sendable {
    public let items: [Moment]
    public let hasMore: Bool
}

/// One page of `GET /moments/{id}/files`.
public struct FilesPage: Decodable, Sendable {
    public let items: [MomentFile]
    public let nextCursorId: String?
    public let hasMore: Bool
}

/// Compact moment as returned by `GET /moments/calendar` (no cover file).
public struct MomentSummary: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let description: String
    public let mediaTypes: [MediaType]
    public let date: DayKey
    public let tz: String
    public let startTime: Date
    public let endTime: Date
}

public struct CalendarDay: Decodable, Sendable, Equatable {
    public let date: DayKey
    public let highlightMoment: MomentSummary?
}

public struct JournalCalendarDay: Decodable, Sendable, Equatable {
    public let date: DayKey
}
