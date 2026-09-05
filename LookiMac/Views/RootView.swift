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
            DayTimelineView()
                .navigationSplitViewColumnWidth(min: 360, ideal: 420)
        } detail: {
            EmptyStateView(title: "Sélectionne un moment", systemImage: "photo.on.rectangle")
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
