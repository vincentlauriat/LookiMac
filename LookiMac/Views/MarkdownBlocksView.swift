import SwiftUI
import LookiKit

/// Renders the blocks produced by `MarkdownBlocks.parse` with native SwiftUI views.
struct MarkdownBlocksView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MarkdownBlocks.parse(markdown).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    inline(text).font(level <= 2 ? .title3.bold() : .headline).padding(.top, 6)
                case .paragraph(let text):
                    inline(text)
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").foregroundStyle(.secondary)
                                inline(item)
                            }
                        }
                    }
                case .image(let alt, let url):
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8))
                        case .failure: Text(alt).font(.caption).foregroundStyle(.secondary)
                        default: ProgressView().frame(height: 80)
                        }
                    }
                    .frame(maxWidth: 480)
                case .rule:
                    Divider()
                }
            }
        }
        .textSelection(.enabled)
    }

    private func inline(_ text: String) -> Text {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(text)
    }
}
