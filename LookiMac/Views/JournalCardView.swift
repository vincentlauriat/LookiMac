import SwiftUI
import LookiKit

struct JournalCardView: View {
    @Environment(AppModel.self) private var model
    let post: JournalPost
    @State private var thumb: NSImage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if post.primaryMedia != nil {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                    if let thumb {
                        Image(nsImage: thumb).resizable().scaledToFill()
                    } else {
                        Image(systemName: post.primaryMedia?.source.mediaType == .video ? "video" : "photo").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.12))
                    Image(systemName: icon).font(.title2).foregroundStyle(Color.accentColor)
                }
                .frame(width: 72, height: 72)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(post.type.label).font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .foregroundStyle(Color.accentColor)
                    Text(time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(post.headline).font(.headline).lineLimit(2)
                if let d = post.description, post.title != nil {
                    Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .task(id: post.id) { thumb = await model.thumbnails.image(for: post) }
    }

    private var icon: String {
        switch post.type {
        case .dailyHealthReport: "heart.text.square"
        case .yesterdayRecap: "text.book.closed"
        case .systemPost: "megaphone"
        default: "doc.text"
        }
    }

    private var time: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR"); f.timeZone = post.timeZone; f.dateFormat = "HH:mm"
        return f.string(from: post.recordedAt)
    }
}
