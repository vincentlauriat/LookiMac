import LookiKit

enum DayState: Equatable {
    case idle
    case loading
    case loaded([Moment])
    case empty
    case failed(LookiError)

    var moments: [Moment] { if case .loaded(let m) = self { m } else { [] } }
}
