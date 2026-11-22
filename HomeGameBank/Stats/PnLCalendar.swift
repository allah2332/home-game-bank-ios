import SwiftUI
import PokerCore

/// Calendar of results: each day (or month, or year) coloured green or red by profit, with totals,
/// a goal for the period and the profit chart for the same period. Tap a day to see or add its sessions.
struct PnLCalendar: View {
    enum Period: String, CaseIterable { case week = "Week", month = "Month", year = "Year", all = "All time" }

    let sessions: [Session]
    @Environment(StatsStore.self) private var store
    @State private var period: Period = LaunchOptions.value("-period").flatMap { v in Period.allCases.first { $0.rawValue.lowercased() == v } } ?? .month
    @State private var anchor = Date()
    @State private var picked: String?
    @State private var addingOn: PickedDay?
    @State private var editing: Session?
    @State private var editingGoal = false
    @State private var goalText = ""

    private let cal = Calendar.current

    private var interval: DateInterval? {
        switch period {
        case .week: return cal.dateInterval(of: .weekOfYear, for: anchor)
        case .month: return cal.dateInterval(of: .month, for: anchor)
        case .year: return cal.dateInterval(of: .year, for: anchor)
        case .all: return nil
        }
    }

    private var inRange: [Session] {
        guard let i = interval else { return sessions }
        let a = SessionStats.dateString(i.start), b = SessionStats.dateString(i.end.addingTimeInterval(-1))
        return sessions.filter { $0.date >= a && $0.date <= b }
    }

    private static let monthTitle: DateFormatter = { let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMMM yyyy"); return f }()
    private static let shortDay: DateFormatter = { let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMM d"); return f }()
    private static let longDay: DateFormatter = { let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEEE, MMM d"); return f }()

    private var title: String {
        guard let i = interval else { return "All time" }
        switch period {
        case .week: return "\(Self.shortDay.string(from: i.start)) – \(Self.shortDay.string(from: i.end.addingTimeInterval(-1)))"
        case .month: return Self.monthTitle.string(from: anchor)
        default: return String(cal.component(.year, from: anchor))
        }
    }

    private func move(_ step: Int) {
        let unit: Calendar.Component = period == .week ? .weekOfYear : period == .month ? .month : .year
        if let d = cal.date(byAdding: unit, value: step, to: anchor) { anchor = d; picked = nil }
    }

    var body: some View {
        let list = inRange
        let sum = SessionStats.summary(list)
        let byDay = Dictionary(grouping: list, by: \.date)
        VStack(alignment: .leading, spacing: 12) {
            PillPicker(options: Period.allCases.map { ($0, $0.rawValue) }, selection: Binding(get: { period }, set: { period = $0; picked = nil }))

            if period != .all {
                HStack {
                    RoundIconButton(symbol: "chevron.left", label: "Previous") { move(-1) }
                    Spacer()
                    Text(title).font(.app(17, .bold)).foregroundStyle(Theme.text)
                    Spacer()
                    RoundIconButton(symbol: "chevron.right", label: "Next") { move(1) }
                }
            }

            HStack(spacing: 10) {
                MiniCard {
                    Text(period == .all ? "Total P&L" : "\(period.rawValue) P&L").font(.app(13)).foregroundStyle(Theme.text2)
                    Text(Money.format(sum.profit, signed: true)).font(.app(24, .bold)).monospacedDigit()
                        .foregroundStyle(Theme.result(sum.profit)).lineLimit(1).minimumScaleFactor(0.6)
                    Text("\(sum.count) session\(sum.count == 1 ? "" : "s") · \(SessionStats.duration(sum.minutes))")
                        .font(.app(12)).foregroundStyle(Theme.text2).lineLimit(1).minimumScaleFactor(0.8)
                }
                if period == .all {
                    let days = Dictionary(grouping: sessions, by: \.date).values.map { $0.reduce(0) { $0 + $1.profit } }
                    let up = days.filter { $0 > 0.004 }.count
                    MiniCard {
                        Text("Winning days").font(.app(13)).foregroundStyle(Theme.text2)
                        Text("\(up)/\(days.count)").font(.app(24, .bold)).monospacedDigit().foregroundStyle(Theme.text)
                        Text(days.isEmpty ? "—" : "\(Int((Double(up) / Double(days.count) * 100).rounded()))% of days played")
                            .font(.app(12)).foregroundStyle(Theme.text2)
                    }
                } else {
                    goalCard(profit: sum.profit)
                }
            }

            grid(byDay: byDay, list: list)

            if let d = picked { dayDetail(d, byDay[d] ?? []) }

            if list.count >= 2 {
                ProfitChart(points: SessionStats.cumulative(list), title: period == .all ? "All-time profit" : "Profit, \(title)")
            }
        }
        .sheet(item: $addingOn) { SessionEditor(original: nil, day: $0.date) }
        .sheet(item: $editing) { SessionEditor(original: $0) }
        .alert("\(period.rawValue)ly goal", isPresented: $editingGoal) {
            TextField("Amount", text: $goalText).keyboardType(.decimalPad)
            Button("Save") { store.setGoal(Double(goalText.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) ?? 0, for: period.rawValue) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("How much do you want to win each \(period.rawValue.lowercased())?") }
    }

    // MARK: goal

    private func goalCard(profit: Double) -> some View {
        let goal = store.goal(for: period.rawValue)
        let progress = goal > 0 ? min(max(profit / goal, 0), 1) : 0
        return Button {
            goalText = goal > 0 ? String(Int(goal)) : ""; editingGoal = true
        } label: {
            MiniCard {
                HStack {
                    Text("\(period.rawValue)ly goal").font(.app(13)).foregroundStyle(Theme.text2)
                    Spacer()
                    Image(systemName: "pencil").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
                }
                if goal > 0 {
                    Text("\(Int((progress * 100).rounded()))%").font(.app(24, .bold)).monospacedDigit().foregroundStyle(progress >= 1 ? Theme.pos : Theme.text)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.fill2)
                            Capsule().fill(Theme.accent).frame(width: g.size.width * progress)
                        }
                    }
                    .frame(height: 6)
                    Text("\(Money.format(max(profit, 0))) of \(Money.format(goal))").font(.app(12)).foregroundStyle(Theme.text2).lineLimit(1).minimumScaleFactor(0.8)
                } else {
                    Text("Set a goal").font(.app(18, .bold)).foregroundStyle(Theme.accent).padding(.vertical, 6)
                    Text("Track progress here").font(.app(12)).foregroundStyle(Theme.text2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: grids

    @ViewBuilder
    private func grid(byDay: [String: [Session]], list: [Session]) -> some View {
        switch period {
        case .week, .month:
            let cols = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
            let syms = cal.shortWeekdaySymbols
            let order = (0..<7).map { syms[($0 + cal.firstWeekday - 1) % 7].uppercased() }
            LazyVGrid(columns: cols, spacing: 5) {
                ForEach(order, id: \.self) { Text($0).font(.app(11, .semibold)).foregroundStyle(Theme.text2) }
                ForEach(Array(dayCells().enumerated()), id: \.offset) { _, d in
                    if let d {
                        let key = SessionStats.dateString(d)
                        let day = byDay[key] ?? []
                        DayCell(number: cal.component(.day, from: d), sessions: day,
                                today: cal.isDateInToday(d), selected: picked == key, tall: period == .week)
                            .onTapGesture { picked = picked == key ? nil : key }
                    } else {
                        Color.clear.frame(height: 1)
                    }
                }
            }
        case .year:
            let byMonth = Dictionary(grouping: list) { Int($0.date.dropFirst(5).prefix(2)) ?? 0 }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(1...12, id: \.self) { m in
                    PeriodCell(label: cal.shortMonthSymbols[m - 1], sessions: byMonth[m] ?? []) {
                        var c = cal.dateComponents([.year], from: anchor); c.month = m; c.day = 15
                        if let d = cal.date(from: c) { anchor = d; period = .month; picked = nil }
                    }
                }
            }
        case .all:
            let byYear = Dictionary(grouping: sessions) { Int($0.date.prefix(4)) ?? 0 }
            let years = byYear.keys.filter { $0 > 0 }.sorted()
            if years.isEmpty {
                Text("No sessions yet").font(.app(14)).foregroundStyle(Theme.text2)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(years.first!...years.last!, id: \.self) { y in
                        PeriodCell(label: String(y), sessions: byYear[y] ?? []) {
                            if let d = cal.date(from: DateComponents(year: y, month: 6, day: 15)) { anchor = d; period = .year; picked = nil }
                        }
                    }
                }
            }
        }
    }

    /// Days to draw, with blanks before the 1st so it lands under the right weekday.
    private func dayCells() -> [Date?] {
        guard let i = interval else { return [] }
        var out: [Date?] = []
        if period == .month {
            let lead = (cal.component(.weekday, from: i.start) - cal.firstWeekday + 7) % 7
            out = Array(repeating: nil, count: lead)
        }
        var d = i.start
        while d < i.end {
            out.append(cal.date(bySettingHour: 12, minute: 0, second: 0, of: d) ?? d)
            guard let n = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = n
        }
        return out
    }

    // MARK: picked day

    private func dayDetail(_ key: String, _ list: [Session]) -> some View {
        let total = list.reduce(0) { $0 + $1.profit }
        let date = SessionStats.day(key) ?? Date()
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Self.longDay.string(from: date)).font(.app(15, .bold)).foregroundStyle(Theme.text)
                Spacer()
                if !list.isEmpty {
                    Text(Money.format(total, signed: true)).font(.app(15, .bold)).monospacedDigit().foregroundStyle(Theme.result(total))
                }
            }
            ForEach(list.sorted { $0.start < $1.start }) { s in
                Button { editing = s } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.game.isEmpty ? (s.isTourney ? "Tournament" : "Cash game") : s.game).font(.app(15, .semibold)).foregroundStyle(Theme.text)
                            Text([s.loc, s.start.isEmpty ? "" : "\(s.start)–\(s.end)", s.mins > 0 ? SessionStats.duration(s.mins) : ""]
                                .filter { !$0.isEmpty }.joined(separator: " · ")).font(.app(12)).foregroundStyle(Theme.text2)
                        }
                        Spacer()
                        Text(Money.format(s.profit, signed: true)).font(.app(15, .bold)).monospacedDigit().foregroundStyle(Theme.result(s.profit))
                    }
                    .padding(.vertical, 4).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button("Add session on \(Self.shortDay.string(from: date))") { addingOn = PickedDay(date: date) }
                .buttonStyle(PillButtonStyle(primary: list.isEmpty))
        }
        .padding(12)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PickedDay: Identifiable { let date: Date; var id: Date { date } }

private struct MiniCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) { content }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(12)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12))
    }
}

private func cellAmount(_ v: Double) -> String { (v > 0.004 ? "+" : "") + Money.short(v) }

private func cellColors(_ sessions: [Session]) -> (bg: Color, edge: Color) {
    guard !sessions.isEmpty else { return (Theme.fill, Theme.fill) }
    let p = sessions.reduce(0) { $0 + $1.profit }
    if p > 0.004 { return (Theme.winBox.opacity(0.35), Theme.winBox) }
    if p < -0.004 { return (Theme.lossBox.opacity(0.35), Theme.lossBox) }
    return (Theme.fill2, Theme.borderStrong)
}

private struct DayCell: View {
    let number: Int
    let sessions: [Session]
    let today: Bool
    let selected: Bool
    var tall = false

    var body: some View {
        let p = sessions.reduce(0) { $0 + $1.profit }
        let c = cellColors(sessions)
        VStack(alignment: .leading, spacing: 2) {
            Text("\(number)").font(.app(11, today ? .bold : .medium)).foregroundStyle(today ? Theme.accent : Theme.text2)
            Spacer(minLength: 0)
            if !sessions.isEmpty {
                Text(cellAmount(p)).font(.app(12, .bold)).monospacedDigit().foregroundStyle(Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(sessions.count == 1 ? "1 sess" : "\(sessions.count) sess").font(.app(9)).foregroundStyle(Theme.text2).lineLimit(1)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, minHeight: tall ? 76 : 58, maxHeight: tall ? 76 : 58, alignment: .topLeading)
        .background(c.bg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.accent : c.edge, lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct PeriodCell: View {
    let label: String
    let sessions: [Session]
    let action: () -> Void

    var body: some View {
        let p = sessions.reduce(0) { $0 + $1.profit }
        let c = cellColors(sessions)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.app(13, .semibold)).foregroundStyle(Theme.text2)
                Text(sessions.isEmpty ? "—" : cellAmount(p)).font(.app(17, .bold)).monospacedDigit().foregroundStyle(Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(sessions.isEmpty ? " " : "\(sessions.count) session\(sessions.count == 1 ? "" : "s")").font(.app(11)).foregroundStyle(Theme.text2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(c.bg, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.edge, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
