import Foundation

struct Banner: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
    let showsSettings: Bool
}
