import SwiftUI
import AVKit
import LookiKit

struct MomentDetailView: View {
    @Environment(AppModel.self) private var model
    let moment: Moment

    @State private var player: AVPlayer?
    @State private var image: NSImage?
    @State private var mediaError: String?
    @State private var retried = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                media
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(moment.title).font(.title2.bold())
                HStack(spacing: 16) {
                    Label(timeRange, systemImage: "clock")
                    Label(duration, systemImage: "timer")
                }
                .font(.callout).foregroundStyle(.secondary)
                if let loc = moment.coverFile?.location {
                    Label(fullAddress(loc), systemImage: "mappin.and.ellipse").font(.callout).foregroundStyle(.secondary)
                }
                if let folder = model.archivedFolder(for: moment.date) {
                    Button { model.reveal(folder) } label: { Label("Révéler dans l'archive", systemImage: "folder.badge.checkmark") }
                        .buttonStyle(.link)
                }
                Divider()
                Text(moment.description).font(.body).textSelection(.enabled)
                if let mediaError {
                    Label(mediaError, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .navigationTitle(moment.title)
        .task(id: moment.id) { await loadMedia() }
        .onDisappear { player?.pause() }
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

    /// Always re-fetch the detail: list URLs may have expired since they were loaded.
    private func loadMedia() async {
        player?.pause(); player = nil; image = nil; mediaError = nil; retried = false
        await fetchAndShow()
    }

    private func fetchAndShow() async {
        do {
            let fresh = try await model.freshMoment(id: moment.id)
            guard let file = fresh.coverFile?.file, let url = file.temporaryURL else {
                mediaError = "Aucun média disponible pour ce moment."; return
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

    /// If the signed URL expired between fetch and playback, fetch once more; then give up with a message.
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

    private var timeRange: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR"); f.timeZone = moment.timeZone; f.dateFormat = "HH:mm"
        return "\(f.string(from: moment.startTime)) – \(f.string(from: moment.endTime))"
    }

    private var duration: String {
        let mn = Int(moment.duration / 60)
        return mn >= 60 ? "\(mn / 60) h \(String(format: "%02d", mn % 60))" : "\(mn) min"
    }

    private func fullAddress(_ l: Location) -> String {
        [l.street, l.subLocality, l.locality].compactMap { $0 }.uniqued().joined(separator: " · ")
    }
}
