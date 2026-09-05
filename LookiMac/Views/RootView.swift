import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Text(model.needsSetup ? "Configure ta clé API dans Réglages." : "Connecté.")
            .padding()
    }
}
