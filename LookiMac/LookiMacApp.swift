import SwiftUI

@main
struct LookiMacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Looki pour Mac") {
            RootView()
                .environment(model)
                .frame(minWidth: 1000, minHeight: 640)
        }
        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
