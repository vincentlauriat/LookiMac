import Foundation

/// Renders a day's moments as the Markdown journal format used by Looki pour Mac.
public enum JournalRenderer {
    public static func render(day: DayKey, moments input: [Moment], journals: [JournalPost] = [], generatedAt: Date, locale: Locale = Locale(identifier: "fr_FR")) -> String {
        let moments = input.sorted { $0.startTime < $1.startTime }
        var out: [String] = []

        out.append("# Journal Looki — \(longDate(day, locale: locale))")
        out.append("")
        if moments.isEmpty {
            out.append("> 0 moment · aucune capture ce jour")
            out.append("")
        } else {
            let total = moments.reduce(0) { $0 + $1.duration }
            let cities = moments.compactMap { $0.coverFile?.location?.locality }.uniqued()
            let cityPart = cities.isEmpty ? "" : " · \(cities.joined(separator: ", "))"
            out.append("> \(moments.count) moments · \(hm(moments.first!)) → \(hmEnd(moments.last!)) · \(durationLong(total)) enregistrées\(cityPart)")
            out.append("")
            out.append("## Chronologie")
            out.append("")
            out.append("| Heure | Moment | Lieu | Média |")
            out.append("|---|---|---|---|")
            for m in moments {
                out.append("| \(range(m)) | [\(m.title)](#\(anchor(m))) | \(place(m)) | \(media(m)) |")
            }
            out.append("")
            out.append("## Récit de la journée")
            out.append("")
            for m in moments {
                out.append("### \(hm(m)) · \(m.title) <a id=\"\(anchor(m))\"></a>")
                out.append("")
                out.append("*\(range(m)) (\(durationShort(m.duration))) · \(place(m))*")
                out.append("")
                out.append(m.description.trimmingCharacters(in: .whitespacesAndNewlines))
                out.append("")
            }
        }
        let posts = journals.filter { !$0.type.isSystem }.sorted { $0.recordedAt > $1.recordedAt }
        if !posts.isEmpty {
            out.append("## Journal Looki")
            out.append("")
            for p in posts {
                out.append("### \(time(p.recordedAt, tz: p.timeZone)) · \(p.type.label) — \(p.headline)")
                out.append("")
                if let d = p.description?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty, d != p.headline {
                    out.append(d); out.append("")
                }
                if let c = p.content?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
                    out.append(c); out.append("")
                }
            }
        }
        out.append("---")
        out.append("")
        let ids = moments.map { "`\($0.id)`" }.joined(separator: ", ")
        let idsPart = moments.isEmpty ? "Aucun identifiant." : "Identifiants des moments : \(ids)."
        let stampTZ = moments.first?.timeZone ?? TimeZone(secondsFromGMT: 7200)!
        out.append("*Généré depuis l'API Looki (`GET /moments?on_date=\(day.string)`) le \(stamp(generatedAt, tz: stampTZ)). \(idsPart)*")
        out.append("")
        return out.joined(separator: "\n")
    }

    // MARK: Helpers

    private static func anchor(_ m: Moment) -> String { String(m.id.prefix(8)) }

    private static func place(_ m: Moment) -> String {
        let label = m.coverFile?.location?.shortLabel ?? ""
        return label.isEmpty ? "?" : label
    }

    private static func media(_ m: Moment) -> String {
        m.mediaTypes.map {
            switch $0 {
            case .video: "vidéo"
            case .image: "photo"
            case .unknown: "autre"
            }
        }.joined(separator: ", ")
    }

    private static func hm(_ m: Moment) -> String { time(m.startTime, tz: m.timeZone) }
    private static func hmEnd(_ m: Moment) -> String { time(m.endTime, tz: m.timeZone) }
    private static func range(_ m: Moment) -> String { "\(hm(m))–\(hmEnd(m))" }

    private static func time(_ d: Date, tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = tz; f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private static func stamp(_ d: Date, tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = tz; f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }

    private static func longDate(_ day: DayKey, locale: Locale) -> String {
        let f = DateFormatter()
        f.locale = locale; f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "EEEE d MMMM yyyy"
        return f.string(from: day.date(in: TimeZone(secondsFromGMT: 0)!))
    }

    /// "3 min" under an hour, "1 h 10" above.
    static func durationShort(_ seconds: TimeInterval) -> String {
        let mn = Int(seconds / 60)
        return mn >= 60 ? "\(mn / 60) h \(String(format: "%02d", mn % 60))" : "\(mn) min"
    }

    /// Always "H h MM" form for the day total.
    static func durationLong(_ seconds: TimeInterval) -> String {
        let mn = Int(seconds / 60)
        return "\(mn / 60) h \(String(format: "%02d", mn % 60))"
    }
}

public extension Array where Element: Hashable {
    /// Order-preserving de-duplication.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
