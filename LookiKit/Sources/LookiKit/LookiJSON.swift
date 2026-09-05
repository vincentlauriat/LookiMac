import Foundation

/// JSON coding configured for the Looki API: snake_case keys and ISO-8601 dates with
/// six fractional digits and a numeric offset (`2026-09-05T10:02:03.568000+02:00`).
public enum LookiJSON {
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unparseable date \(s)"))
        }
        return d
    }

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(formatDate(date))
        }
        return e
    }

    // DateFormatter is not Sendable; the lock serialises access to the shared instances.
    nonisolated(unsafe) private static let fractional: DateFormatter = make("yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX")
    nonisolated(unsafe) private static let fractional3: DateFormatter = make("yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX")
    nonisolated(unsafe) private static let plain: DateFormatter = make("yyyy-MM-dd'T'HH:mm:ssXXXXX")
    private static let lock = NSLock()

    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = format
        return f
    }

    static func parseDate(_ s: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return fractional.date(from: s) ?? fractional3.date(from: s) ?? plain.date(from: s)
    }

    static func formatDate(_ d: Date) -> String {
        lock.lock(); defer { lock.unlock() }
        return fractional.string(from: d)
    }
}

public extension TimeZone {
    /// Parses `"+02:00"`, `"-05:30"` or `"Z"`.
    static func fromOffset(_ s: String) -> TimeZone? {
        if s == "Z" { return TimeZone(secondsFromGMT: 0) }
        let sign: Int
        switch s.first {
        case "+": sign = 1
        case "-": sign = -1
        default: return nil
        }
        let body = s.dropFirst().split(separator: ":")
        guard body.count == 2, let h = Int(body[0]), let m = Int(body[1]),
              (0...14).contains(h), (0..<60).contains(m) else { return nil }
        return TimeZone(secondsFromGMT: sign * (h * 3600 + m * 60))
    }
}
