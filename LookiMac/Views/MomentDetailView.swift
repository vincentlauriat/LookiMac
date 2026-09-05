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
    @State private var clips: [MomentFile] = []
    @State private var clipsState: ClipsState = .loading
    @State private var selectedClip: MomentFile?

    private enum ClipsState: Equatable { case loading, loaded, failed(String) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                media
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                gallery

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
        .task(id: moment.id) { await loadClips() }
        .onDisappear { player?.pause() }
    }

    // MARK: Clip gallery

    @ViewBuilder private var gallery: some View {
        switch clipsState {
        case .loading:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Chargement des clips…") }
                .font(.callout).foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary)
        case .loaded where clips.count <= 1:
            EmptyView()
        case .loaded:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(clips.count) clips").font(.headline)
                    if selectedClip != nil {
                        Button("Couverture") { selectedClip = nil; Task { await loadMedia() } }
                            .buttonStyle(.link).font(.callout)
                    }
                }
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(clips) { clip in
                            ClipThumbnail(clip: clip, isSelected: clip.id == selectedClip?.id, timeZone: moment.timeZone)
                                .onTapGesture { Task { await show(clip: clip) } }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.automatic)
            }
        }
    }

    private func loadClips() async {
        clipsState = .loading; clips = []; selectedClip = nil
        do {
            clips = try await model.clips(of: moment.id)
            clipsState = .loaded
        } catch let e as LookiError {
            clipsState = .failed(e.userMessage)
        } catch {
            clipsState = .failed(error.localizedDescription)
        }
    }

    /// Plays or displays one clip in the main media area.
    private func show(clip: MomentFile) async {
        selectedClip = clip
        player?.pause(); player = nil; image = nil; mediaError = nil; retried = true   // no expiry retry for clips: the list is fresh
        guard let url = clip.file.temporaryURL else { mediaError = "URL absente pour ce clip."; return }
        await present(file: clip.file, url: url)
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
            await present(file: file, url: url)
        } catch let e as LookiError {
            mediaError = e.userMessage
        } catch {
            mediaError = error.localizedDescription
        }
    }

    private func present(file: RemoteFile, url: URL) async {
        switch file.mediaType {
        case .video:
            let item = AVPlayerItem(url: url)
            let p = AVPlayer(playerItem: item)
            player = p
            observeFailure(of: item)
        case .image, .unknown:
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                image = NSImage(data: data)
                if image == nil { mediaError = "Image illisible." }
            } catch {
                mediaError = error.localizedDescription
            }
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

private struct ClipThumbnail: View {
    @Environment(AppModel.self) private var model
    let clip: MomentFile
    let isSelected: Bool
    let timeZone: TimeZone
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        Color.secondary.opacity(0.15)
                            .overlay(Image(systemName: clip.file.mediaType == .video ? "video" : "photo").foregroundStyle(.secondary))
                    }
                }
                .frame(width: 112, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
                if clip.file.mediaType == .video, let ms = clip.file.metadata?.durationMs {
                    Text(durationLabel(ms)).font(.caption2.monospacedDigit())
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.white).padding(4)
                }
            }
            Text(time).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .task(id: clip.id) { image = await model.thumbnails.image(for: clip) }
        .accessibilityLabel("Clip de \(time)")
        .accessibilityAddTraits(.isButton)
    }

    private var time: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR"); f.timeZone = timeZone; f.dateFormat = "HH:mm:ss"
        return f.string(from: clip.createdAt)
    }

    private func durationLabel(_ ms: Int) -> String {
        let s = ms / 1000
        return s >= 60 ? "\(s / 60):\(String(format: "%02d", s % 60))" : "\(s) s"
    }
}
