import SwiftUI
import PokerCore

/// Every host form on the Current game tab.
struct GameSheetView: View {
    @Environment(ClubStore.self) private var club
    @Environment(\.dismiss) private var dismiss
    let sheet: GameSheet

    var body: some View {
        NavigationStack {
            content
                .scrollContentBackground(.hidden)
                .background(Theme.surface)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationBackground(Theme.surface)
    }

    @ViewBuilder private var content: some View {
        let l = club.ledger
        if let g = l.openGame {
            switch sheet {
            case .start: StartGameForm()
            case .newPlayer(let amt): NewPlayerForm(game: g, amount: amt)
            case .buyIn(let pid):
                AmountForm(title: "Buy-in · \(l.name(pid))", note: "Bought in \(Money.format(l.summary(g.id).seat(pid)?.buyIn ?? 0)) so far",
                           initial: g.buyIn, button: "Buy in") { a in
                    club.addEntry(["gameId": g.id, "playerId": pid, "kind": "buyin", "amount": a], toast: "\(l.name(pid)) bought in \(Money.format(a))")
                }
            case .subtract(let pid):
                let had = l.summary(g.id).seat(pid)?.buyIn ?? 0
                AmountForm(title: "Subtract · \(l.name(pid))", note: "Bought in \(Money.format(had))", initial: min(g.buyIn, had), max: had, button: "Subtract") { a in
                    club.addEntry(["gameId": g.id, "playerId": pid, "kind": "buyin", "amount": -a], toast: "\(l.name(pid))'s buy-in reduced by \(Money.format(a))")
                }
            case .cashOut(let pid):
                let seat = l.summary(g.id).seat(pid)
                AmountForm(title: "Cash out · \(l.name(pid))", note: "Bought in \(Money.format(seat?.buyIn ?? 0))" + ((seat?.isCashedOut ?? false) ? " · already cashed \(Money.format(seat!.cashOut))" : ""),
                           initial: nil, allowZero: true, button: "Cash out") { a in
                    club.addEntry(["gameId": g.id, "playerId": pid, "kind": "cashout", "amount": a], toast: "\(l.name(pid)) cashed out \(Money.format(a))")
                }
            case .close: CloseForm(ledger: l, game: g)
            case .drops(let hh):
                let per = hh ? g.hhDrop : g.drop
                AmountForm(title: hh ? "High hand drop" : "Jackpot drop", note: "Number of hands at \(Money.format(per)) each", initial: 10, wholeNumber: true, button: "Add") { n in
                    let h = Int(n)
                    club.addEntry(["gameId": g.id, "kind": hh ? "hhdrop" : "drop", "amount": (Double(h) * per * 100).rounded() / 100, "hands": h],
                                  toast: "\(Money.format(Double(h) * per)) added")
                }
            case .hit: BadBeatForm(ledger: l, game: g)
            case .payout: PayoutForm(ledger: l, game: g)
            case .adjustJackpot:
                AmountForm(title: "Adjust jackpot", note: "Negative takes money out", initial: nil, allowNegative: true, button: "Save") { a in
                    club.addEntry(["gameId": g.id, "kind": "jpadjust", "amount": a], toast: "Jackpot adjusted \(Money.format(a, signed: true))")
                }
            case .recordHigh: HighHandForm(ledger: l, game: g)
            case .payHigh: PayHighForm(ledger: l, game: g)
            case .highSettings: HighSettingsForm(game: g)
            }
        } else if sheet == .start {
            StartGameForm()
        } else {
            Text("No game running").foregroundStyle(Theme.text2)
        }
    }
}

/// One amount field and a confirm button.
private struct AmountForm: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let note: String
    let initial: Double?
    var max: Double? = nil
    var allowZero = false
    var allowNegative = false
    var wholeNumber = false
    let button: String
    let onSave: (Double) -> Void
    @State private var text = ""

    private var value: Double? { Double(text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) }
    private var ok: Bool {
        guard let v = value else { return false }
        if let max, v > max + 0.001 { return false }
        if wholeNumber && v != v.rounded() { return false }
        return allowNegative ? v != 0 : (allowZero ? v >= 0 : v > 0)
    }

    var body: some View {
        Form {
            Section {
                TextField("Amount", text: $text).keyboardType(allowNegative ? .numbersAndPunctuation : (wholeNumber ? .numberPad : .decimalPad))
                    .font(.app(28, .bold)).monospacedDigit()
            } footer: { Text(note) }
        }
        .navigationTitle(title)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(button) { onSave(value ?? 0); dismiss() }.bold().disabled(!ok) } }
        .onAppear { if let initial { text = initial == initial.rounded() ? String(Int(initial)) : String(initial) } }
    }
}

private struct StartGameForm: View {
    @Environment(ClubStore.self) private var club
    @Environment(\.dismiss) private var dismiss
    @State private var name = Date().formatted(.dateTime.weekday(.wide)) + " game"
    @State private var buyIn = ""
    @State private var after = false
    @State private var drop = ""
    @State private var hhFixed = false
    @State private var hhPrize = "100"
    @State private var hhDrop = ""
    @State private var hhTimer = ""

    var body: some View {
        let last = club.ledger.games.max { $0.createdAt < $1.createdAt }
        Form {
            Section {
                TextField("Name", text: $name)
                LabeledField(title: "Default buy-in", text: $buyIn)
                Picker("Money", selection: $after) {
                    Text("Collect before").tag(false)
                    Text("Collect after").tag(true)
                }
            }
            if club.settings.bbj { Section("Bad beat jackpot") { LabeledField(title: "Drop per hand", text: $drop) } }
            if club.settings.hh {
                Section("High hand") {
                    Picker("Prize", selection: $hhFixed) {
                        Text("Pot from a drop").tag(false)
                        Text("Set amount").tag(true)
                    }
                    if hhFixed { LabeledField(title: "Prize", text: $hhPrize) } else { LabeledField(title: "Drop per hand", text: $hhDrop) }
                    LabeledField(title: "Timer, minutes", text: $hhTimer)
                }
            }
        }
        .navigationTitle("Start a game")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Start") {
                    let prize = hhFixed ? Swift.max(0, Double(hhPrize) ?? 0) : 0
                    club.startGame(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Home game" : name,
                                   buyIn: Double(buyIn) ?? (last?.buyIn ?? 20), drop: Double(drop) ?? (last?.drop ?? 1), collectAfter: after,
                                   hhDrop: Double(hhDrop) ?? (last?.hhDrop ?? 1), hhPrize: prize, hhTimer: Int(hhTimer) ?? 0)
                    dismiss()
                }.bold()
            }
        }
        .onAppear {
            buyIn = StandingsText.plain(last?.buyIn ?? 20); drop = StandingsText.plain(last?.drop ?? 1)
            hhDrop = StandingsText.plain(last?.hhDrop ?? 1); after = last?.collectAfter ?? false
            if let p = last?.hhPrize, p > 0 { hhFixed = true; hhPrize = StandingsText.plain(p) }
            if let t = last?.hhTimer, t > 0 { hhTimer = String(t) }
        }
    }
}

enum StandingsText {
    static func plain(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v) }
}

private struct NewPlayerForm: View {
    @Environment(ClubStore.self) private var club
    @Environment(\.dismiss) private var dismiss
    let game: Game
    let amount: Double
    @State private var name = ""
    var body: some View {
        Form {
            Section { TextField("Name", text: $name).textInputAutocapitalization(.words) } footer: { Text("Seated with a \(Money.format(amount)) buy-in") }
        }
        .navigationTitle("New player")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add & buy in") {
                    let n = name.trimmingCharacters(in: .whitespaces)
                    if club.players.contains(where: { $0.name.lowercased() == n.lowercased() }) { club.message = "\(n) is already on the roster."; return }
                    if let id = club.addPlayer(n) {
                        club.addEntry(["gameId": game.id, "playerId": id, "kind": "buyin", "amount": amount], toast: "\(n) bought in \(Money.format(amount))")
                    }
                    dismiss()
                }
                .bold().disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

private struct CloseForm: View {
    @Environment(ClubStore.self) private var club
    @Environment(\.dismiss) private var dismiss
    let ledger: Ledger
    let game: Game
    var body: some View {
        let s = ledger.summary(game.id)
        let notOut = s.seats.filter { !$0.seat.isCashedOut }.map { ledger.name($0.playerId) }
        let h = ledger.highHand(game.id)
        Form {
            Section {
                Text("Buy-ins \(Money.format(s.buy)) · drop \(Money.format(s.drop))" + (s.hh > 0 ? " · high hand \(Money.format(s.hh))" : "") + " · cash-outs \(Money.format(s.out))")
                    .font(.app(14)).foregroundStyle(Theme.text2)
                if Ledger.bigChipsTotal(game) > 0 { Text("Big chips still out: \(Money.format(Ledger.bigChipsTotal(game))). Collect them first.").foregroundStyle(Theme.neg) }
                if !notOut.isEmpty { Text("Not cashed out: \(notOut.joined(separator: ", ")). They'll be settled at $0.").foregroundStyle(Theme.neg) }
                if ledger.settings.hh, let h, game.hhPrize > 0 || ledger.highHandPool.balance > 0 {
                    Text("High hand not paid: \(ledger.name(h.playerId)) · \(Ledger.handText(h)).").foregroundStyle(Theme.neg)
                }
            }
            Section { SettleView(ledger: ledger, game: game, final: true) }
        }
        .navigationTitle("Settle \(game.name)")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Close game") {
                    club.updateGame(game.id, ["status": "closed", "closedAt": ClubStore.now], toast: "Game settled")
                    dismiss()
                }.bold()
            }
        }
    }
}

private struct BadBeatForm: View {
    @Environment(ClubStore.self) private var club
    @Environment(\.dismiss) private var dismiss
    let ledger: Ledger
    let game: Game
    @State private var loser = ""
    @State private var winner = ""
    @State private var active = Set<String>()

    var body: some View {
        let s = ledger.summary(game.id)
        let ids = s.seats.map(\.playerId).sorted { ledger.name($0) < ledger.name($1) }
        let jp = ledger.jackpot.balance
        let sh = Ledger.hitShares(balance: jp, split: ledger.settings.split, loser: loser, winner: winner, active: Array(active))
        Form {
            Section {
                Picker("Lost the hand", selection: $loser) { ForEach(ids, id: \.self) { Text(ledger.name($0)).tag($0) } }
                Picker("Won the hand", selection: $winner) { ForEach(ids, id: \.self) { Text(ledger.name($0)).tag($0) } }
            } footer: { Text("Jackpot \(Money.format(jp)) · loser \(Int(ledger.settings.split.loser))%, winner \(Int(ledger.settings.split.winner))%, table \(Int(ledger.settings.split.table))%") }
            Section("Sharing the table's part") {
                ForEach(ids.filter { $0 != loser && $0 != winner }, id: \.self) { id in
                    Toggle(ledger.name(id), isOn: Binding(get: { active.contains(id) }, set: { if $0 { active.insert(id) } else { active.remove(id) } }))
                }
            }
            Section("Payout") {
                if loser == winner { Text("Pick two different players.").foregroundStyle(Theme.neg) } else {
                    PayLine(name: ledger.name(loser), tag: "lost the hand", amount: sh.loser)
                    PayLine(name: ledger.name(winner), tag: "won the hand", amount: sh.winner)
                    ForEach(sh.table, id: \.self) { PayLine(name: ledger.name($0), tag: "table share", amount: sh.each) }
                    if sh.left > 0.004 { Text("\(Money.format(sh.left)) stays in the jackpot").font(.app(13)).foregroundStyle(Theme.text2) }
                }
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: Theme.accent))
        .navigationTitle("Bad beat hit")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Pay out") {
                    let now = ClubStore.now
                    let rows = [(loser, sh.loser, "Bad beat · lost the hand"), (winner, sh.winner, "Bad beat · won the hand")] + sh.table.map { ($0, sh.each, "Bad beat · table share") }
                    for (i, r) in rows.enumerated() where r.1 > 0 {
                        club.addEntry(["ts": now + Double(i), "gameId": game.id, "playerId": r.0, "kind": "jackpot", "amount": r.1, "note": r.2])
                    }
                    club.message = "Bad beat paid · \(Money.format(rows.reduce(0) { $0 + $1.1 }))"
                    dismiss()
                }
                .bold().disabled(loser == winner || loser.isEmpty)
            }
        }
        .onAppear {
            loser = ids.first ?? ""; winner = ids.dropFirst().first ?? ""
            active = Set(s.seats.filter { !$0.seat.isCashedOut }.map(\.playerId))
        }
    }
}

private struct PayLine: View {
    let name: String, tag: String, amount: Double
    var body: some View {
        HStack { Text(name); Text(tag).font(.app(12)).foregroundStyle(Theme.text2); Spacer(); Text(Money.format(amount)).bold().monospacedDigit() }
    }
}

private struct PayoutForm: View {
    @Environment(ClubStore.self) private var club
    @Environment(\.dismiss) private var dismiss
    let ledger: Ledger
    let game: Game
    @State private var pid = ""
    @State private var amount = ""
    @State private var note = ""
    var body: some View {
        let bal = ledger.jackpot.balance, v = Double(amount) ?? 0
        Form {
            Section {
                Picker("Player", selection: $pid) { ForEach(ledger.players.values.sorted { $0.name < $1.name }) { Text($0.name).tag($0.id) } }
                LabeledField(title: "Amount", text: $amount)
                TextField("Note", text: $note)
            } footer: { Text("Jackpot \(Money.format(bal))") }
        }
        .navigationTitle("Pay from jackpot")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Pay") {
                    club.addEntry(["gameId": game.id, "playerId": pid, "kind": "jackpot", "amount": v, "note": note], toast: "\(ledger.name(pid)) paid \(Money.format(v))")
                    dismiss()
                }.bold().disabled(pid.isEmpty || v <= 0 || v > bal + 0.001)
            }
        }
        .onAppear { pid = ledger.summary(game.id).seats.first?.playerId ?? ledger.players.keys.first ?? "" }
    }
}

private struct HighHandForm: View {
    @Environment(ClubStore.self) private var club
    @Environment(\.dismiss) private var dismiss
    let ledger: Ledger
    let game: Game
    @State private var pid = ""
    @State private var rank = 0
    @State private var note = ""
    var body: some View {
        let h = ledger.highHand(game.id), minRank = max(0, h?.rank ?? 0)
        let ids = ledger.summary(game.id).seats.map(\.playerId).sorted { ledger.name($0) < ledger.name($1) }
        Form {
            Section {
                Picker("Player", selection: $pid) { ForEach(ids, id: \.self) { Text(ledger.name($0)).tag($0) } }
                Picker("Hand", selection: $rank) {
                    ForEach(minRank..<Ledger.highHands.count, id: \.self) { Text(Ledger.highHands[$0]).tag($0) }
                }
                TextField("Details (Kings, aces full…)", text: $note)
            } footer: { if let h { Text("To beat: \(ledger.name(h.playerId)) · \(Ledger.handText(h))") } }
        }
        .navigationTitle(h == nil ? "Record high hand" : "New high hand")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    club.addEntry(["gameId": game.id, "playerId": pid, "kind": "highhand", "rank": rank, "note": note.trimmingCharacters(in: .whitespaces)],
                                  toast: "\(ledger.name(pid)) has the high hand")
                    dismiss()
                }.bold().disabled(pid.isEmpty)
            }
        }
        .onAppear { pid = ids.first ?? ""; rank = minRank }
    }
}

private struct PayHighForm: View {
    @Environment(ClubStore.self) private var club
    @Environment(\.dismiss) private var dismiss
    let ledger: Ledger
    let game: Game
    @State private var pid = ""
    @State private var amount = ""
    var body: some View {
        let h = ledger.highHand(game.id), pool = ledger.highHandPool.balance, prize = game.hhPrize, v = Double(amount) ?? 0
        let ids = ledger.summary(game.id).seats.map(\.playerId).sorted { ledger.name($0) < ledger.name($1) }
        Form {
            Section {
                Picker("Winner", selection: $pid) { ForEach(ids, id: \.self) { Text(ledger.name($0)).tag($0) } }
                LabeledField(title: "Amount", text: $amount)
            } footer: { Text(prize > 0 ? "Paid by the house" : "Pot \(Money.format(pool))") }
        }
        .navigationTitle("Pay high hand")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Pay out") {
                    var f: [String: Any] = ["gameId": game.id, "playerId": pid, "kind": "hhpay", "amount": v, "note": Ledger.handText(h)]
                    if prize > 0 { f["fixed"] = true }
                    club.addEntry(f, toast: "\(ledger.name(pid)) paid \(Money.format(v)) for the high hand")
                    if game.hhTimer > 0 { club.updateGame(game.id, ["hhTimerStart": ClubStore.now]) }
                    dismiss()
                }.bold().disabled(pid.isEmpty || v <= 0 || (prize <= 0 && v > pool + 0.001))
            }
        }
        .onAppear { pid = h?.playerId ?? ids.first ?? ""; amount = StandingsText.plain(prize > 0 ? prize : pool) }
    }
}

private struct HighSettingsForm: View {
    @Environment(ClubStore.self) private var club
    @Environment(\.dismiss) private var dismiss
    let game: Game
    @State private var fixed = false
    @State private var prize = ""
    @State private var drop = ""
    @State private var timer = ""
    var body: some View {
        Form {
            Section {
                Picker("Prize", selection: $fixed) {
                    Text("Pot from a drop").tag(false)
                    Text("Set amount").tag(true)
                }
                if fixed { LabeledField(title: "Prize", text: $prize) } else { LabeledField(title: "Drop per hand", text: $drop) }
                LabeledField(title: "Timer, minutes", text: $timer)
            }
        }
        .navigationTitle("High hand")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let t = max(0, Int(timer) ?? 0)
                    var f: [String: Any] = ["hhPrize": fixed ? max(0, Double(prize) ?? 0) : 0, "hhDrop": max(0, Double(drop) ?? game.hhDrop), "hhTimer": t]
                    if t != game.hhTimer { f["hhTimerStart"] = t > 0 ? ClubStore.now : NSNull() }
                    club.updateGame(game.id, f, toast: "High hand settings saved")
                    dismiss()
                }.bold().disabled(fixed && (Double(prize) ?? 0) <= 0)
            }
        }
        .onAppear {
            fixed = game.hhPrize > 0; prize = StandingsText.plain(game.hhPrize > 0 ? game.hhPrize : 100)
            drop = StandingsText.plain(game.hhDrop); timer = game.hhTimer > 0 ? String(game.hhTimer) : ""
        }
    }
}
