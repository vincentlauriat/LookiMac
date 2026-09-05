import SwiftUI

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var detail: String? = nil
    var body: some View {
        ContentUnavailableView { Label(title, systemImage: systemImage) } description: { if let detail { Text(detail) } }
    }
}
