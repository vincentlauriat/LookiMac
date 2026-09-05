import SwiftUI
import LookiKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            CalendarSidebarView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 320)
        } content: {
            Group {
                if model.isSearchMode { SearchResultsView() }
                else if model.sidebarMode == .journal { JournalFeedView() }
                else { DayTimelineView() }
            }
            .navigationSplitViewColumnWidth(min: 360, ideal: 420)
        } detail: {
            if model.sidebarMode == .journal, !model.isSearchMode, let p = model.selectedPost {
                JournalPostDetailView(post: p)
            } else if let m = model.selectedMoment {
                MomentDetailView(moment: m)
            } else {
                EmptyStateView(title: model.sidebarMode == .journal ? "Sélectionne un post" : "Sélectionne un moment",
                               systemImage: model.sidebarMode == .journal ? "book" : "photo.on.rectangle")
            }
        }
        .searchable(text: $model.searchQuery, placement: .toolbar, prompt: "Rechercher un souvenir…")
        .onSubmit(of: .search) { Task { await model.runSearch() } }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.archiveSelectedDay()
                } label: { Label("Archiver ce jour", systemImage: "arrow.down.doc") }
                .disabled(model.isSearchMode || (model.dayState.moments.isEmpty && !model.hasJournal(for: model.selectedDay)) || model.isArchiving)
                .help("Télécharge les médias du jour et écrit journal.md dans le dossier d'archive")

                Button { model.openArchiveRoot() } label: { Label("Dossier d'archive", systemImage: "folder") }
                    .disabled(model.archiveRoot == nil)
            }
        }
        .sheet(isPresented: Binding(get: { model.archiveProgress != nil }, set: { if !$0 { model.dismissArchiveProgress() } })) {
            ArchiveProgressView().environment(model)
        }
        .safeAreaInset(edge: .top) {
            if let banner = model.banner {
                HStack {
                    Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "info.circle")
                    Text(banner.text)
                    Spacer()
                    if banner.showsSettings { Button("Réglages…") { openSettings() } }
                    Button { model.banner = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                .padding(8)
                .background(banner.isError ? Color.red.opacity(0.15) : Color.yellow.opacity(0.15))
            }
        }
        .task {
            if model.needsSetup {
                model.banner = Banner(text: "Aucune clé API : ouvre les Réglages pour te connecter à Looki.", isError: true, showsSettings: true)
                openSettings()
            } else {
                model.select(day: model.selectedDay)
            }
        }
        .onChange(of: model.needsSetup) { _, needs in
            if !needs { model.banner = nil; model.select(day: model.selectedDay) }
        }
    }
}
