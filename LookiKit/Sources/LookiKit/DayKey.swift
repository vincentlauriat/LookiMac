import Foundation

/// A calendar day identified as `YYYY-MM-DD`, the unit the Looki API uses for `on_date`.
public struct DayKey: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Accepts strictly `YYYY-MM-DD` and validates the date against the Gregorian calendar.
    public init?(string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d)
        else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let firstOfMonth = cal.date(from: DateComponents(year: y, month: m, day: 1)),
              let range = cal.range(of: .day, in: .month, for: firstOfMonth),
              range.contains(d)
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public init(date: Date, timeZone: TimeZone) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    public var string: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var pathComponents: [String] {
        [String(format: "%04d", year), String(format: "%02d", month), String(format: "%02d", day)]
    }

    public var description: String { string }

    /// Midnight at the start of this day in `tz`.
    public func date(in tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // Codable as a plain "YYYY-MM-DD" string.
    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let k = DayKey(string: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid DayKey \(s)"))
        }
        self = k
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(string)
    }
}
