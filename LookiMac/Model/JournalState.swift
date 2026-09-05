import LookiKit

enum SidebarMode: String { case moments, journal }

enum JournalState: Equatable {
    case idle, loading, loaded
    case failed(LookiError)
}
