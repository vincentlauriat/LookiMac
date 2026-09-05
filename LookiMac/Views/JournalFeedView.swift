import SwiftUI
import LookiKit

struct JournalFeedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.journalState {
            case .idle, .loading:
                ProgressView("Chargement du journal…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let e):
                EmptyStateView(title: e.userMessage, systemImage: "wifi.exclamationmark", detail: "Vérifie ta connexion ou ta clé API.")
                    .overlay(alignment: .bottom) {
                        Button("Réessayer") { Task { await model.loadJournal(force: true) } }.padding()
                    }
            case .loaded:
                if model.visibleJournalDays.isEmpty {
                    EmptyStateView(title: "Aucun post dans le journal", systemImage: "book.closed",
                                   detail: "Looki génère le journal à partir de tes moments, en général le soir.")
                } else {
                    ScrollViewReader { proxy in
                        List(selection: $model.selectedPost) {
                            ForEach(model.visibleJournalDays, id: \.date) { day in
                                Section(header: Text(dayTitle(day.date)).id(day.date)) {
                                    ForEach(day.journals) { post in
                                        JournalCardView(post: post).tag(post)
                                    }
                                }
                            }
                        }
                        .listStyle(.inset)
                        .onChange(of: model.selectedDay) { _, day in
                            if let target = model.visibleJournalDays.first(where: { $0.date <= day })?.date {
                                withAnimation { proxy.scrollTo(target, anchor: .top) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Journal")
        .navigationSubtitle(subtitle)
        .task { await model.loadJournal() }
    }

    private var subtitle: String {
        let n = model.visibleJournalDays.reduce(0) { $0 + $1.journals.count }
        return n == 0 ? "" : "\(n) post\(n > 1 ? "s" : "")"
    }

    private func dayTitle(_ day: DayKey) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR"); f.timeZone = model.localTimeZone; f.dateFormat = "EEEE d MMMM yyyy"
        return f.string(from: day.date(in: model.localTimeZone)).capitalized
    }
}
