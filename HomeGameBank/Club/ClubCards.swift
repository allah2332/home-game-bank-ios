import SwiftUI
import UIKit
import PokerCore

struct StatCard: View {
    let title: String, value: String, foot: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.app(13, .medium)).foregroundStyle(Theme.text2)
            Text(value).font(.app(26, .bold)).monospacedDigit().foregroundStyle(Theme.text).minimumScaleFactor(0.6).lineLimit(1)
            Text(foot).font(.app(12)).foregroundStyle(Theme.text2).lineLimit(2)
        }
        .cardSurface()
    }
}

struct BoardCard: View {
    @Environment(ClubStore.self) private var club
    let ledger: Ledger
    @State private var editing: Ledger.BoardRow?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All-time winnings").font(.app(18, .bold)).foregroundStyle(Theme.text)
            if ledger.board.isEmpty {
                Text("No settled games yet").font(.app(14)).foregroundStyle(Theme.text2)
            }
            ForEach(Array(ledger.board.enumerated()), id: \.element.id) { i, r in
                Button { if club.canEdit { editing = r } } label: {
                    HStack(spacing: 10) {
                        Text("\(i + 1)").font(.app(14)).monospacedDigit().foregroundStyle(Theme.text2).frame(width: 22, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(r.name).font(.app(16, .semibold)).foregroundStyle(Theme.text)
                                if r.bbj > 0 { Tag("BBJ") }
                                if r.hh > 0 { Tag("HH") }
                                if r.edited { Tag("Edited") }
                            }
                            Text("\(r.games) game\(r.games == 1 ? "" : "s") · \(Money.format(r.buyIn)) in").font(.app(12)).foregroundStyle(Theme.text2)
                        }
                        Spacer()
                        Text(Money.format(r.net, signed: true)).font(.app(16, .bold)).monospacedDigit().foregroundStyle(Theme.result(r.net))
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .cardSurface()
        .sheet(item: $editing) { r in StandingsEditor(row: r) }
    }
}

struct Tag: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.app(10, .semibold)).foregroundStyle(Theme.text2)
            .padding(.horizontal, 6).padding(.vertical, 1).background(Theme.fill, in: Capsule())
    }
}

/// Host edits a player's standings. Saved as an adjustment, so real game history isn't changed.
private struct StandingsEditor: View {
    @Environment(ClubStore.self) private var club
    @Environment(\.dismiss) private var dismiss
    let row: Ledger.BoardRow
    @State private var net = ""
    @State private var buyIn = ""
    @State private var games = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Show for \(row.name)") {
                    LabeledField(title: "Net", text: $net)
                    LabeledField(title: "Bought in", text: $buyIn)
                    LabeledField(title: "Games", text: $games)
                    TextField("Note", text: $note)
                }
            }
            .scrollContentBackground(.hidden).background(Theme.surface)
            .navigationTitle("Edit standings").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.bold() }
            }
            .onAppear {
                net = Self.plain(row.net); buyIn = Self.plain(row.buyIn); games = String(row.games)
            }
        }
        .presentationBackground(Theme.surface)
    }

    static func plain(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v) }

    private func save() {
        let dn = (Double(net) ?? row.net) - row.net, db = (Double(buyIn) ?? row.buyIn) - row.buyIn, dg = (Int(games) ?? row.games) - row.games
        if abs(dn) > 0.004 || abs(db) > 0.004 || dg != 0 {
            club.addEntry(["playerId": row.id, "kind": "adjust", "amount": dn, "buyins": db, "games": dg, "note": note.trimmingCharacters(in: .whitespaces)],
                          toast: "\(row.name)'s standings updated")
        }
        dismiss()
    }
}

struct LabeledField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: $text).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).monospacedDigit()
        }
    }
}

/// Host only: game options, both codes, and what players can see.
struct HostSettings: View {
    @Environment(ClubStore.self) private var club
    @State private var editingSplit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Game options").font(.app(18, .bold)).foregroundStyle(Theme.text)
            Toggle("Bad beat jackpot", isOn: Binding(get: { club.settings.bbj }, set: { v in club.updateSettings({ $0.bbj = v }, toast: "Bad beat jackpot \(v ? "on" : "off")") }))
            if club.settings.bbj {
                Button { editingSplit = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Jackpot split").foregroundStyle(Theme.text)
                            let s = club.settings.split
                            Text("Loser \(Int(s.loser))% · Winner \(Int(s.winner))% · Table \(Int(s.table))%").font(.app(12)).foregroundStyle(Theme.text2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.text2)
                    }
                }
                .buttonStyle(.plain)
            }
            Toggle("High hand", isOn: Binding(get: { club.settings.hh }, set: { v in club.updateSettings({ $0.hh = v }, toast: "High hand \(v ? "on" : "off")") }))

            Text("Codes").font(.app(18, .bold)).foregroundStyle(Theme.text).padding(.top, 8)
            if let code = club.code { CodeRow(label: "Player code", code: code) }
            if let key = club.hostKey, let code = club.code { CodeRow(label: "Host code", code: "\(code)-\(key)") }

            Text("What players see").font(.app(18, .bold)).foregroundStyle(Theme.text).padding(.top, 8)
            ForEach(ClubSettings.Show.allCases, id: \.self) { s in
                Toggle(s.label, isOn: Binding(get: { club.settings.shows(s) },
                                              set: { v in club.updateSettings({ $0.show[s.rawValue] = v }, toast: "Players \(v ? "can" : "can't") see: \(s.label.lowercased())") }))
            }
        }
        .font(.app(16))
        .toggleStyle(SwitchToggleStyle(tint: Theme.accent))
        .cardSurface()
        .sheet(isPresented: $editingSplit) { SplitEditor() }
    }
}

private struct CodeRow: View {
    let label: String, code: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(Theme.text)
            Spacer()
            Text(code).font(.app(15, .bold)).monospaced().foregroundStyle(Theme.text)
            Button { UIPasteboard.general.string = code } label: { Image(systemName: "doc.on.doc") }.foregroundStyle(Theme.text2)
                .accessibilityLabel("Copy \(label.lowercased())")
        }
    }
}

private struct SplitEditor: View {
    @Environment(ClubStore.self) private var club
    @Environment(\.dismiss) private var dismiss
    @State private var loser = ""
    @State private var winner = ""
    @State private var table = ""

    private var total: Double { (Double(loser) ?? 0) + (Double(winner) ?? 0) + (Double(table) ?? 0) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledField(title: "Loser of the hand %", text: $loser)
                    LabeledField(title: "Winner of the hand %", text: $winner)
                    LabeledField(title: "Rest of the table %", text: $table)
                }
                Section { Text("Total \(Int(total.rounded()))%").foregroundStyle(abs(total - 100) < 0.01 ? Theme.text2 : Theme.neg) }
            }
            .scrollContentBackground(.hidden).background(Theme.surface)
            .navigationTitle("Jackpot split").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let s = JackpotSplit(loser: Double(loser) ?? 0, winner: Double(winner) ?? 0, table: Double(table) ?? 0)
                        club.updateSettings({ $0.split = s }, toast: "Jackpot split saved")
                        dismiss()
                    }
                    .bold().disabled(abs(total - 100) > 0.01)
                }
            }
            .onAppear {
                let s = club.settings.split
                loser = StandingsEditor.plain(s.loser); winner = StandingsEditor.plain(s.winner); table = StandingsEditor.plain(s.table)
            }
        }
        .presentationBackground(Theme.surface)
    }
}
