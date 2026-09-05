import SwiftUI
import LookiKit

struct DayTimelineView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.dayState {
            case .idle, .loading:
                ProgressView("Chargement…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                EmptyStateView(title: "Aucun moment ce jour", systemImage: "moon.zzz", detail: "Looki n'a rien capturé le \(model.selectedDay.string).")
            case .failed(let e):
                EmptyStateView(title: e.userMessage, systemImage: "wifi.exclamationmark", detail: "Vérifie ta connexion ou ta clé API.")
                    .overlay(alignment: .bottom) {
                        Button("Réessayer") { Task { await model.reloadSelectedDay(force: true) } }.padding()
                    }
            case .loaded(let moments):
                List(moments, selection: $model.selectedMoment) { m in
                    MomentRowView(moment: m).tag(m)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(dayTitle)
        .navigationSubtitle(subtitle)
    }

    private var dayTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR"); f.timeZone = model.localTimeZone; f.dateFormat = "EEEE d MMMM yyyy"
        return f.string(from: model.selectedDay.date(in: model.localTimeZone)).capitalized
    }

    private var subtitle: String {
        let n = model.dayState.moments.count
        return n == 0 ? "" : "\(n) moment\(n > 1 ? "s" : "")"
    }
}
