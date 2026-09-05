import SwiftUI
import LookiKit

struct SearchResultsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if let e = model.searchError {
                EmptyStateView(title: e.userMessage, systemImage: "exclamationmark.magnifyingglass")
            } else if model.searchResults.isEmpty && !model.isSearching {
                EmptyStateView(title: "Aucun souvenir trouvé", systemImage: "magnifyingglass", detail: "Essaie d'autres mots : lieu, activité, objet, personne.")
            } else {
                List(selection: $model.selectedMoment) {
                    ForEach(model.searchResults) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            MomentRowView(moment: m)
                            Text(m.date.string).font(.caption2).foregroundStyle(.tertiary)
                        }
                        .tag(m)
                    }
                    if model.searchHasMore {
                        HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                            .task { await model.loadMoreSearch() }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Recherche")
        .navigationSubtitle(model.isSearching && model.searchResults.isEmpty ? "Recherche en cours…" : "\(model.searchResults.count) résultat\(model.searchResults.count > 1 ? "s" : "")")
        .task(id: model.searchQuery) {
            try? await Task.sleep(for: .milliseconds(350))   // debounce typing
            guard !Task.isCancelled else { return }
            await model.runSearch()
        }
    }
}
