import SwiftUI

struct ArchiveProgressView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let p = model.archiveProgress {
            VStack(alignment: .leading, spacing: 12) {
                Text(p.finished ? "Archive terminée" : (p.error == nil ? "Archivage en cours…" : "Archivage interrompu")).font(.headline)
                ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                Text("\(p.done)/\(p.total) · \(p.skipped) ignoré\(p.skipped > 1 ? "s" : "") · \(p.lastMessage)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let error = p.error { Text(error).foregroundStyle(.red).font(.callout) }
                HStack {
                    Spacer()
                    if p.finished || p.error != nil {
                        if let folder = p.folder { Button("Afficher dans le Finder") { model.reveal(folder) } }
                        Button("Fermer") { model.dismissArchiveProgress() }.keyboardShortcut(.defaultAction)
                    } else {
                        Button("Annuler", role: .cancel) { model.cancelArchive() }
                    }
                }
            }
            .padding(20)
            .frame(width: 420)
        }
    }
}
