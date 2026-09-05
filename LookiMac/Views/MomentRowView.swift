import SwiftUI
import LookiKit

struct MomentRowView: View {
    @Environment(AppModel.self) private var model
    let moment: Moment
    @State private var thumb: NSImage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                if let thumb {
                    Image(nsImage: thumb).resizable().scaledToFill()
                } else {
                    Image(systemName: moment.mediaTypes.contains(.video) ? "video" : "photo").foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(timeRange).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text(moment.title).font(.headline).lineLimit(2)
                if let place = moment.coverFile?.location?.shortLabel, !place.isEmpty {
                    Label(place, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    ForEach(moment.mediaTypes, id: \.self) { t in
                        Image(systemName: t == .video ? "video.fill" : "photo.fill").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .task(id: moment.coverFile?.id) { thumb = await model.thumbnails.image(for: moment) }
    }

    private var timeRange: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR"); f.timeZone = moment.timeZone; f.dateFormat = "HH:mm"
        return "\(f.string(from: moment.startTime)) – \(f.string(from: moment.endTime))"
    }
}
