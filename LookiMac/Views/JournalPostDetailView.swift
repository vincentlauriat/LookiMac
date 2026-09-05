import SwiftUI
import AVKit
import LookiKit

struct JournalPostDetailView: View {
    @Environment(AppModel.self) private var model
    let post: JournalPost

    @State private var player: AVPlayer?
    @State private var image: NSImage?
    @State private var mediaError: String?
    @State private var retried = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if post.primaryMedia != nil {
                    media
                        .frame(maxWidth: .infinity)
                        .aspectRatio(aspect, contentMode: .fit)
                        .frame(maxHeight: 520)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                HStack(spacing: 8) {
                    Text(post.type.label).font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .foregroundStyle(Color.accentColor)
                    Text(stamp).font(.callout).foregroundStyle(.secondary)
                }
                if let t = post.title { Text(t).font(.title2.bold()) }
                if let d = post.description, !d.isEmpty {
                    Text(d).font(post.title == nil ? .title3 : .body).textSelection(.enabled)
                }
                if let c = post.content, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Divider()
                    MarkdownBlocksView(markdown: c)
                }
                if let mediaError {
                    Label(mediaError, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .navigationTitle(post.headline)
        .task(id: post.id) { await loadMedia() }
        .onDisappear { player?.pause() }
    }

    private var aspect: CGFloat {
        guard let m = post.primaryMedia?.source.metadata, let w = m.width, let h = m.height, w > 0, h > 0 else { return 1 }
        return CGFloat(w) / CGFloat(h)
    }

    @ViewBuilder private var media: some View {
        if let player {
            VideoPlayer(player: player)
        } else if let image {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadMedia() async {
        player?.pause(); player = nil; image = nil; mediaError = nil; retried = false
        guard post.primaryMedia != nil else { return }
        await fetchAndShow()
    }

    /// Always re-fetch the post: the feed's signed URLs may have expired.
    private func fetchAndShow() async {
        do {
            let fresh = try await model.freshJournal(id: post.id)
            guard let file = fresh.primaryMedia?.source, let url = file.temporaryURL else {
                mediaError = "Aucun média disponible."; return
            }
            switch file.mediaType {
            case .video:
                let item = AVPlayerItem(url: url)
                let p = AVPlayer(playerItem: item)
                player = p
                observeFailure(of: item)
            case .image, .unknown:
                let (data, _) = try await URLSession.shared.data(from: url)
                image = NSImage(data: data)
                if image == nil { mediaError = "Image illisible." }
            }
        } catch let e as LookiError {
            mediaError = e.userMessage
        } catch {
            mediaError = error.localizedDescription
        }
    }

    private func observeFailure(of item: AVPlayerItem) {
        Task { @MainActor in
            for await status in item.publisher(for: \.status).values {
                if status == .failed {
                    if !retried { retried = true; player = nil; await fetchAndShow() }
                    else { mediaError = "La vidéo n'a pas pu être lue (lien expiré ?)." }
                    return
                }
                if status == .readyToPlay { return }
            }
        }
    }

    private var stamp: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR"); f.timeZone = post.timeZone; f.dateFormat = "EEEE d MMMM · HH:mm"
        return f.string(from: post.recordedAt)
    }
}
