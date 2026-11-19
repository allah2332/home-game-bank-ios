import SwiftUI
import UniformTypeIdentifiers
import PokerCore

struct StatsView: View {
    enum TypeFilter: String, CaseIterable { case all = "All", cash = "Cash", tourney = "Tourney" }
    enum ViewMode: Hashable { case overall, group(SessionStats.Grouping) }

    @Environment(StatsStore.self) private var store
    @State private var type: TypeFilter = .all
    @State private var mode: ViewMode = LaunchOptions.value("-view").flatMap { v in SessionStats.Grouping.allCases.first { $0.rawValue.lowercased() == v } }.map { ViewMode.group($0) } ?? .overall
    @State private var adding = false
    @State private var editing: Session?
    @State private var importing = false
    @State private var bankText = ""
    @State private var editingBank = false
    @State private var notice: String?

    private var list: [Session] {
        store.sessions.filter { type == .all || ($0.isTourney == (type == .tourney)) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("My stats").font(.app(22, .bold)).foregroundStyle(Theme.text)
                    Spacer()
                    Button("Add session") { adding = true }.buttonStyle(PillButtonStyle(primary: true))
                }
                PillPicker(options: TypeFilter.allCases.map { ($0, $0.rawValue) }, selection: $type)
                PillPicker(options: [(ViewMode.overall, "Overall")] + SessionStats.Grouping.allCases.map { (ViewMode.group($0), $0.rawValue) }, selection: $mode)

                let l = list
                if l.isEmpty {
                    Text("No sessions yet").font(.app(15)).foregroundStyle(Theme.text2).padding(.vertical, 8)
                } else if case .group(let g) = mode {
                    GroupTable(rows: SessionStats.groups(l, by: g))
                } else {
                    if l.count >= 2 { ProfitChart(points: SessionStats.cumulative(l)) }
                    Overview(summary: SessionStats.summary(l),
                             bankroll: store.startBankroll + store.sessions.reduce(0) { $0 + $1.profit })
                }

                if !l.isEmpty {
                    Text("Sessions").font(.app(15, .bold)).foregroundStyle(Theme.text).padding(.top, 8)
                    ForEach(l.sorted { $0.date != $1.date ? $0.date > $1.date : $0.ts > $1.ts }.prefix(40)) { s in
                        Button { editing = s } label: { SessionRow(s: s) }.buttonStyle(.plain)
                    }
                }

                HStack(spacing: 8) {
                    Button("Starting bankroll \(Money.format(store.startBankroll))") {
                        bankText = store.startBankroll == 0 ? "" : String(store.startBankroll); editingBank = true
                    }
                    ShareLink(item: store.backupFile()) { Text("Back up") }.disabled(store.sessions.isEmpty)
                    Button("Restore") { importing = true }
                }
                .font(.app(14, .medium)).foregroundStyle(Theme.text2).buttonStyle(.plain)
                .padding(.top, 8)
            }
            .cardSurface()
            .padding(12)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $adding) { SessionEditor(original: nil) }
        .sheet(item: $editing) { SessionEditor(original: $0) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                if let r = try? store.restore(from: url) {
                    notice = "Restored \(r.0) session\(r.0 == 1 ? "" : "s") (\(r.1) new)"
                } else { notice = "That file isn't a session backup." }
            case .failure: notice = "Couldn't open that file."
            }
        }
        .alert("Starting bankroll", isPresented: $editingBank) {
            TextField("Amount", text: $bankText).keyboardType(.decimalPad)
            Button("Save") { store.setStartBankroll(Double(bankText.replacingOccurrences(of: ",", with: "")) ?? 0) }
            Button("Cancel", role: .cancel) {}
        }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }
}

private struct Overview: View {
    let summary: SessionStats.Summary
    let bankroll: Double

    var body: some View {
        let s = summary
        func pct(_ a: Int, _ b: Int) -> Int { b > 0 ? Int((Double(a) / Double(b) * 100).rounded()) : 0 }
        return VStack(spacing: 0) {
            StatRow(label: "Profit/loss", value: Money.format(s.profit, signed: true), color: Theme.result(s.profit))
            StatRow(label: "Per hour", value: s.perHour.map { Money.format($0, signed: true) } ?? "—", color: s.perHour.map { _ in Theme.result(s.profit) } ?? Theme.text)
            StatRow(label: "Per session", value: s.perSession.map { Money.format($0, signed: true) } ?? "—", color: Theme.result(s.profit))
            StatRow(label: "Time played", value: SessionStats.duration(s.minutes))
            StatRow(label: "Winning sessions", value: "\(s.wins)/\(s.count) (\(pct(s.wins, s.count))%)")
            if s.tourneys > 0 { StatRow(label: "Tournaments cashed", value: "\(s.cashed)/\(s.tourneys) (\(pct(s.cashed, s.tourneys))%)") }
            StatRow(label: "Tips/meals", value: Money.format(s.tips))
            StatRow(label: "Bankroll", value: Money.format(bankroll))
        }
    }
}

private struct StatRow: View {
    let label: String
    let value: String
    var color: Color = Theme.text
    var body: some View {
        HStack {
            Text(label).font(.app(16)).foregroundStyle(Theme.text)
            Spacer()
            Text(value).font(.app(16, .bold)).monospacedDigit().foregroundStyle(color)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

private struct GroupTable: View {
    let rows: [SessionStats.Group]
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Name"); Spacer(); Text("$"); Text("Hours").frame(width: 64, alignment: .trailing)
            }
            .font(.app(12)).foregroundStyle(Theme.text2).padding(.bottom, 6)
            ForEach(rows) { r in
                HStack(spacing: 12) {
                    Text(r.label).font(.app(16, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer()
                    Text(Money.format(r.profit, signed: true)).font(.app(16, .bold)).monospacedDigit().foregroundStyle(Theme.result(r.profit))
                    Text("\(r.hours)").font(.app(16, .bold)).monospacedDigit().foregroundStyle(.white)
                        .padding(.trailing, 10).frame(width: 64, height: 34, alignment: .trailing)
                        .background(r.profit > 0.004 ? Theme.winBox : r.profit < -0.004 ? Theme.lossBox : Theme.fill2,
                                    in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
            }
        }
    }
}

private struct SessionRow: View {
    let s: Session
    private static let short: DateFormatter = { let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMM d"); return f }()
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.game.isEmpty ? (s.isTourney ? "Tournament" : "Cash game") : s.game).font(.app(16, .semibold)).foregroundStyle(Theme.text)
                Text([SessionStats.day(s.date).map { Self.short.string(from: $0) } ?? s.date, s.loc, s.mins > 0 ? SessionStats.duration(s.mins) : ""]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.app(13)).foregroundStyle(Theme.text2)
            }
            Spacer()
            Text(Money.format(s.profit, signed: true)).font(.app(16, .bold)).monospacedDigit().foregroundStyle(Theme.result(s.profit))
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}
