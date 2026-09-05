import SwiftUI
import LookiKit

struct CalendarSidebarView: View {
    @Environment(AppModel.self) private var model

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = model.localTimeZone
        c.locale = Locale(identifier: "fr_FR")
        return c
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            weekdayRow
            grid
            Spacer()
        }
        .padding(12)
        .navigationTitle("Looki")
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(monthTitle).font(.headline)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(isCurrentMonth)
            }
            .buttonStyle(.borderless)
            Button("Aujourd'hui") { model.select(day: AppModel.today(in: model.localTimeZone)) }
                .font(.caption).buttonStyle(.link)
        }
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.calendar = cal; f.locale = cal.locale; f.timeZone = cal.timeZone; f.dateFormat = "LLLL yyyy"
        return f.string(from: firstOfMonth).capitalized
    }

    private var firstOfMonth: Date {
        DayKey(year: model.visibleMonth.year, month: model.visibleMonth.month, day: 1).date(in: model.localTimeZone)
    }

    private var isCurrentMonth: Bool {
        let t = AppModel.today(in: model.localTimeZone)
        return (t.year, t.month) == model.visibleMonth
    }

    private var weekdayRow: some View {
        let symbols = cal.veryShortStandaloneWeekdaySymbols   // Sunday-first
        let ordered = Array(symbols[1...]) + [symbols[0]]      // Monday-first
        return HStack {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, s in
                Text(s).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let days = cal.range(of: .day, in: .month, for: firstOfMonth)!.count
        let weekday = cal.component(.weekday, from: firstOfMonth)   // 1 = Sunday
        let leading = (weekday + 5) % 7                              // Monday-first offset
        let today = AppModel.today(in: model.localTimeZone)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
            ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 32) }
            ForEach(1...days, id: \.self) { d in
                let key = DayKey(year: model.visibleMonth.year, month: model.visibleMonth.month, day: d)
                DayCell(day: d, count: model.monthMarks[key], isSelected: key == model.selectedDay, isFuture: key > today)
                    .onTapGesture { if key <= today { model.select(day: key) } }
            }
        }
    }

    private func shift(_ delta: Int) {
        let date = cal.date(byAdding: .month, value: delta, to: firstOfMonth)!
        let c = cal.dateComponents([.year, .month], from: date)
        model.showMonth(year: c.year!, month: c.month!)
    }
}

private struct DayCell: View {
    let day: Int
    let count: Int?        // nil = not fetched yet, 0 = fetched and empty
    let isSelected: Bool
    let isFuture: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text("\(day)").font(.callout.monospacedDigit())
            Circle().frame(width: 5, height: 5)
                .foregroundStyle((count ?? 0) > 0 ? Color.accentColor : .clear)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
        .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color.accentColor.opacity(0.2) : .clear))
        .foregroundStyle(isFuture ? .tertiary : (count == 0 ? .secondary : .primary))
        .contentShape(Rectangle())
        .accessibilityLabel(count.map { "\(day), \($0) moments" } ?? "\(day)")
    }
}
