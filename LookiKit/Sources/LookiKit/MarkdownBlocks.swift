import Foundation

public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullets([String])
    case image(alt: String, url: URL)
    case rule
}

/// Minimal block-level Markdown parser covering what the Looki API emits.
/// Inline syntax (bold, links) is left in the strings for `AttributedString(markdown:)`.
public enum MarkdownBlocks {
    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
        }
        func flushBullets() {
            if !bullets.isEmpty { blocks.append(.bullets(bullets)); bullets = [] }
        }
        func flushAll() { flushParagraph(); flushBullets() }

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flushAll(); continue }

            if let heading = parseHeading(line) { flushAll(); blocks.append(heading); continue }
            if line == "---" || line == "***" { flushAll(); blocks.append(.rule); continue }
            if let image = parseImage(line) { flushAll(); blocks.append(image); continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                bullets.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                continue
            }
            flushBullets()
            paragraph.append(line)
        }
        flushAll()
        return blocks
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.count > hashes,
              line[line.index(line.startIndex, offsetBy: hashes)] == " " else { return nil }
        return .heading(level: hashes, text: String(line.dropFirst(hashes)).trimmingCharacters(in: .whitespaces))
    }

    /// Matches a whole line of the form `![alt](url)`. An unparseable URL degrades to a paragraph with the alt text.
    private static func parseImage(_ line: String) -> MarkdownBlock? {
        guard line.hasPrefix("!["), let close = line.firstIndex(of: "]"),
              line.index(after: close) < line.endIndex, line[line.index(after: close)] == "(", line.hasSuffix(")") else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<close])
        let urlString = String(line[line.index(close, offsetBy: 2)..<line.index(before: line.endIndex)])
        if let url = URL(string: urlString), url.scheme != nil { return .image(alt: alt, url: url) }
        return .paragraph(alt)
    }
}
