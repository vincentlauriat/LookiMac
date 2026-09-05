import AppKit
import AVFoundation
import Observation
import LookiKit

@MainActor
@Observable
final class ThumbnailLoader {
    typealias FreshMoment = @Sendable (String) async throws -> Moment
    typealias FreshPost = @Sendable (String) async throws -> JournalPost

    private let cache: MomentCache
    private let freshMoment: FreshMoment
    private let freshPost: FreshPost
    private let memory = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    init(cache: MomentCache, freshMoment: @escaping FreshMoment, freshPost: @escaping FreshPost) {
        self.cache = cache
        self.freshMoment = freshMoment
        self.freshPost = freshPost
        memory.countLimit = 400
    }

    func image(for moment: Moment) async -> NSImage? {
        guard let file = moment.coverFile else { return nil }
        let key = file.id
        if let img = memory.object(forKey: key as NSString) { return img }
        if let task = inFlight[key] { return await task.value }
        let task = Task<NSImage?, Never> { [cache, freshMoment] in
            if let data = await cache.thumbnail(for: key), let img = NSImage(data: data) { return img }
            // Prefer the URL we already have (list call); fall back to a fresh detail if it is gone.
            var url = file.file.temporaryURL
            if url == nil { url = try? await freshMoment(moment.id).coverFile?.file.temporaryURL }
            guard let url else { return nil }
            guard let jpeg = await Self.makeJPEG(from: url, mediaType: file.file.mediaType) else { return nil }
            try? await cache.storeThumbnail(jpeg, for: key)
            return NSImage(data: jpeg)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { memory.setObject(result, forKey: key as NSString) }
        return result
    }

    func image(for post: JournalPost) async -> NSImage? {
        guard let media = post.primaryMedia else { return nil }
        let key = "j-\(post.id)"
        if let img = memory.object(forKey: key as NSString) { return img }
        if let task = inFlight[key] { return await task.value }
        let task = Task<NSImage?, Never> { [cache, freshPost] in
            if let data = await cache.thumbnail(for: key), let img = NSImage(data: data) { return img }
            var file = media.thumbnail ?? media.source
            if file.temporaryURL == nil, let fresh = try? await freshPost(post.id), let m = fresh.primaryMedia { file = m.thumbnail ?? m.source }
            guard let url = file.temporaryURL, let jpeg = await Self.makeJPEG(from: url, mediaType: file.mediaType) else { return nil }
            try? await cache.storeThumbnail(jpeg, for: key)
            return NSImage(data: jpeg)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { memory.setObject(result, forKey: key as NSString) }
        return result
    }

    /// Thumbnail of one clip: the API preview when present, else a frame/downscale of the clip itself.
    func image(for clip: MomentFile) async -> NSImage? {
        let key = "c-\(clip.id)"
        if let img = memory.object(forKey: key as NSString) { return img }
        if let task = inFlight[key] { return await task.value }
        let task = Task<NSImage?, Never> { [cache] in
            if let data = await cache.thumbnail(for: key), let img = NSImage(data: data) { return img }
            let file = clip.thumbnail?.temporaryURL != nil ? clip.thumbnail! : clip.file
            guard let url = file.temporaryURL, let jpeg = await Self.makeJPEG(from: url, mediaType: file.mediaType) else { return nil }
            try? await cache.storeThumbnail(jpeg, for: key)
            return NSImage(data: jpeg)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { memory.setObject(result, forKey: key as NSString) }
        return result
    }

    /// Downloads an image, or grabs a frame of a remote video, and returns JPEG data.
    nonisolated private static func makeJPEG(from url: URL, mediaType: MediaType) async -> Data? {
        let cgImage: CGImage?
        switch mediaType {
        case .image, .unknown:
            guard let (data, _) = try? await URLSession.shared.data(from: url), let img = NSImage(data: data) else { return nil }
            cgImage = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        case .video:
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            cgImage = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        }
        guard let cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}
