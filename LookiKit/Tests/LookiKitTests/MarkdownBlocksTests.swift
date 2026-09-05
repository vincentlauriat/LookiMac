import Testing
import Foundation
@testable import LookiKit

@Suite struct MarkdownBlocksTests {
    @Test func parsesRecap() {
        let md = "### Exploration\n\n- **Robots**: analyse.\n- **Lunettes**: convergence.\n\n### Soirée\n\nDîner aux chandelles\npour clore.\n"
        #expect(MarkdownBlocks.parse(md) == [
            .heading(level: 3, text: "Exploration"),
            .bullets(["**Robots**: analyse.", "**Lunettes**: convergence."]),
            .heading(level: 3, text: "Soirée"),
            .paragraph("Dîner aux chandelles pour clore."),
        ])
    }

    @Test func parsesImagesRulesAndArrows() {
        let md = "### Les premiers jours\n![first_day](https://public-file.example.test/1.png)\nQuelques moments\n\n↓\n\n---\n* item\n"
        #expect(MarkdownBlocks.parse(md) == [
            .heading(level: 3, text: "Les premiers jours"),
            .image(alt: "first_day", url: URL(string: "https://public-file.example.test/1.png")!),
            .paragraph("Quelques moments"),
            .paragraph("↓"),
            .rule,
            .bullets(["item"]),
        ])
    }

    @Test func invalidImageURLBecomesParagraphAndEmptyIsEmpty() {
        #expect(MarkdownBlocks.parse("![x](not a url)") == [.paragraph("x")])
        #expect(MarkdownBlocks.parse("") == [])
        #expect(MarkdownBlocks.parse("   \n\n") == [])
        #expect(MarkdownBlocks.parse("# H1\n###### H6\n####### not a heading") == [.heading(level: 1, text: "H1"), .heading(level: 6, text: "H6"), .paragraph("####### not a heading")])
    }
}
