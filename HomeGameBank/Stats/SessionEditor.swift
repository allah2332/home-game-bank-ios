import SwiftUI
import PokerCore

/// Add or edit a session. New sessions end now and start 4 hours earlier, dated the day they started.
struct SessionEditor: View {
    let original: Session?
    @Environment(StatsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var type: String
    @State private var date: Date
    @State private var start: Date
    @State private var end: Date
    @State private var game: String
    @State private var loc: String
    @State private var buy: String
    @State private var out: String
    @State private var tips: String
    @State private var confirmDelete = false

    init(original: Session?) {
        self.original = original
        let now = Date(), began = now.addingTimeInterval(-4 * 3600)
        func time(_ t: String, fallback: Date) -> Date {
            let p = t.split(separator: ":").compactMap { Int($0) }
            guard p.count == 2 else { return fallback }
            return Calendar.current.date(bySettingHour: p[0], minute: p[1], second: 0, of: now) ?? fallback
        }
        if let s = original {
            let st = time(s.start, fallback: Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now)
            _type = State(initialValue: s.type)
            _date = State(initialValue: SessionStats.day(s.date) ?? now)
            _start = State(initialValue: st)
            _end = State(initialValue: time(s.end, fallback: st.addingTimeInterval(Double(s.mins) * 60)))
            _game = State(initialValue: s.game)
            _loc = State(initialValue: s.loc)
            _buy = State(initialValue: Self.plain(s.buy))
            _out = State(initialValue: Self.plain(s.out))
            _tips = State(initialValue: s.tips > 0 ? Self.plain(s.tips) : "")
        } else {
            _type = State(initialValue: "cash")
            _date = State(initialValue: began)
            _start = State(initialValue: began)
            _end = State(initialValue: now)
            _game = State(initialValue: "")
            _loc = State(initialValue: "")
            _buy = State(initialValue: "")
            _out = State(initialValue: "")
            _tips = State(initialValue: "")
        }
    }

    private static func plain(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }
    private static func num(_ s: String) -> Double { max(0, Double(s.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) ?? 0) }

    private var minutes: Int { SessionStats.spanMinutes(start: SessionStats.timeString(start), end: SessionStats.timeString(end)) }
    private var result: Double { Self.num(out) - Self.num(buy) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        Text("Cash game").tag("cash")
                        Text("Tournament").tag("tourney")
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
                }
                Section {
                    SuggestField(title: "Game", text: $game, prompt: "NL Hold'em", suggestions: unique(store.sessions.map(\.game)))
                    SuggestField(title: "Location", text: $loc, prompt: "", suggestions: unique(store.sessions.map(\.loc)))
                }
                Section {
                    MoneyField(title: "Buy-in", text: $buy)
                    MoneyField(title: "Cash-out", text: $out)
                    MoneyField(title: "Tips/meals", text: $tips)
                }
                Section {
                    HStack {
                        Text("Length \(SessionStats.duration(minutes))").foregroundStyle(Theme.text2)
                        Spacer()
                        if !buy.isEmpty || !out.isEmpty {
                            Text("Result ").foregroundColor(Theme.text2) + Text(Money.format(result, signed: true)).bold().foregroundColor(Theme.result(result))
                        }
                    }
                    .font(.app(15))
                }
                if original != nil {
                    Section {
                        Button("Delete session", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .navigationTitle(original == nil ? "Add session" : "Edit session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.bold() }
            }
            .confirmationDialog("Delete this session?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let o = original { store.delete(id: o.id) }
                    dismiss()
                }
            }
        }
        .presentationBackground(Theme.surface)
    }

    private func unique(_ a: [String]) -> [String] {
        var seen = Set<String>()
        return a.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func save() {
        let s = Session(id: original?.id ?? Session.newID(), ts: original?.ts ?? Date().timeIntervalSince1970 * 1000,
                        type: type, date: SessionStats.dateString(date),
                        start: SessionStats.timeString(start), end: SessionStats.timeString(end), mins: minutes,
                        game: String(game.trimmingCharacters(in: .whitespaces).prefix(40)),
                        loc: String(loc.trimmingCharacters(in: .whitespaces).prefix(40)),
                        buy: Self.num(buy), out: Self.num(out), tips: Self.num(tips))
        store.upsert(s)
        dismiss()
    }
}

private struct MoneyField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("$0", text: $text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
        }
    }
}

/// Text field with a menu of earlier values, so "SIENA" is one tap instead of retyping it.
private struct SuggestField: View {
    let title: String
    @Binding var text: String
    let prompt: String
    let suggestions: [String]
    var body: some View {
        HStack {
            Text(title)
            TextField(title, text: $text, prompt: Text(prompt)).multilineTextAlignment(.trailing).autocorrectionDisabled()
            if !suggestions.isEmpty {
                Menu {
                    ForEach(suggestions, id: \.self) { s in Button(s) { text = s } }
                } label: {
                    Image(systemName: "chevron.down.circle.fill").foregroundStyle(Theme.text2)
                }
                .accessibilityLabel("Earlier \(title.lowercased())s")
            }
        }
    }
}
