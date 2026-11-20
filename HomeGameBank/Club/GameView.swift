import SwiftUI
import UIKit
import PokerCore

/// Current game tab.
struct GameView: View {
    @Environment(ClubStore.self) private var club
    @State private var sheet: GameSheet?
    @State private var confirmBuy: (pid: String, amount: Double)?

    var body: some View {
        let l = club.ledger
        ScrollView {
            VStack(spacing: 12) {
                ClubHeader()
                if let g = l.openGame {
                    GameCard(ledger: l, game: g, sheet: $sheet, confirmBuy: $confirmBuy)
                    if l.settings.bbj && club.sees(.jackpot) { JackpotCard(ledger: l, game: g, sheet: $sheet) }
                    if l.settings.hh && club.sees(.highhand) { HighHandCard(ledger: l, game: g, sheet: $sheet) }
                    if club.sees(.log) { LogCard(ledger: l, game: g) }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No game running").font(.app(18, .bold)).foregroundStyle(Theme.text)
                        if club.canEdit { Button("Start a game") { sheet = .start }.buttonStyle(PillButtonStyle(primary: true)) }
                    }
                    .cardSurface()
                }
                if club.canEdit { HostSettings() }
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $sheet) { s in GameSheetView(sheet: s) }
        .confirmationDialog(confirmTitle(l), isPresented: Binding(get: { confirmBuy != nil }, set: { if !$0 { confirmBuy = nil } }), titleVisibility: .visible) {
            if let c = confirmBuy, let g = l.openGame {
                Button("Buy in \(Money.format(c.amount))") {
                    club.addEntry(["gameId": g.id, "playerId": c.pid, "kind": "buyin", "amount": c.amount], toast: "\(l.name(c.pid)) bought in \(Money.format(c.amount))")
                    confirmBuy = nil
                }
            }
        }
    }

    private func confirmTitle(_ l: Ledger) -> String {
        guard let c = confirmBuy, let g = l.openGame else { return "" }
        let n = (l.summary(g.id).seat(c.pid)?.buys ?? 0) + 1
        return "\(l.name(c.pid)) · \(n == 1 ? "first buy-in" : "buy-in #\(n)")\(g.collectAfter ? "" : " · collect \(Money.format(c.amount)) now")"
    }
}

enum GameSheet: Identifiable, Hashable {
    case start, newPlayer(seatAmount: Double), buyIn(String), subtract(String), cashOut(String), close
    case drops(highHand: Bool), hit, payout, adjustJackpot
    case recordHigh, payHigh, highSettings
    var id: String { String(describing: self) }
}

private struct GameCard: View {
    @Environment(ClubStore.self) private var club
    let ledger: Ledger
    let game: Game
    @Binding var sheet: GameSheet?
    @Binding var confirmBuy: (pid: String, amount: Double)?
    @State private var seatPick = ""
    @State private var seatAmount = ""
    @State private var confirmDelete = false

    var body: some View {
        let s = ledger.summary(game.id), amounts = club.sees(.amounts)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.name).font(.app(20, .bold)).foregroundStyle(Theme.text)
                    Text("Buy-in \(Money.format(game.buyIn)) · \(game.collectAfter ? "Collect after" : "Collect before")").font(.app(13)).foregroundStyle(Theme.text2)
                }
                Spacer()
                if club.sees(.pot) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Pot").font(.app(12)).foregroundStyle(Theme.text2)
                        Text(Money.format(s.onTable)).font(.app(24, .bold)).monospacedDigit().foregroundStyle(Theme.text)
                    }
                }
            }

            if s.seats.isEmpty { Text("Nobody seated").font(.app(14)).foregroundStyle(Theme.text2) }
            ForEach(s.seats) { x in
                let pid = x.playerId, seat = x.seat
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(ledger.name(pid)).font(.app(16, .semibold)).foregroundStyle(Theme.text)
                            if seat.isCashedOut { Tag("Cashed out") }
                        }
                        if amounts {
                            Text("\(seat.buys)× · in \(Money.format(seat.buyIn))" + (seat.isCashedOut ? " · out \(Money.format(seat.cashOut))" : ""))
                                .font(.app(12)).monospacedDigit().foregroundStyle(Theme.text2)
                        }
                    }
                    Spacer()
                    if amounts && seat.isCashedOut {
                        Text(Money.format(seat.net, signed: true)).font(.app(15, .bold)).monospacedDigit().foregroundStyle(Theme.result(seat.net))
                    }
                    if club.canEdit {
                        Button("+\(Money.format(game.buyIn))") { confirmBuy = (pid, game.buyIn) }.buttonStyle(PillButtonStyle())
                        Menu {
                            Button("Buy-in…") { sheet = .buyIn(pid) }
                            Button("Subtract from buy-in…") { sheet = .subtract(pid) }.disabled(seat.buyIn <= 0)
                            Button("Cash out…") { sheet = .cashOut(pid) }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).frame(width: 36, height: 36)
                                .foregroundStyle(Theme.text).background(Theme.fill, in: Circle())
                        }
                        .accessibilityLabel("More for \(ledger.name(pid))")
                    }
                }
                .padding(.vertical, 4)
            }

            if club.canEdit {
                let notSeated = ledger.players.values.filter { s.seat($0.id) == nil }.sorted { $0.name < $1.name }
                HStack(spacing: 8) {
                    Picker("Player", selection: $seatPick) {
                        ForEach(notSeated) { Text($0.name).tag($0.id) }
                        Text("+ New player…").tag("__new")
                    }
                    .pickerStyle(.menu).tint(Theme.text)
                    TextField(Money.format(game.buyIn), text: $seatAmount).keyboardType(.decimalPad).frame(width: 70)
                        .padding(.horizontal, 10).frame(height: 40).background(Theme.fill, in: RoundedRectangle(cornerRadius: 10))
                    Button("Seat") {
                        let amt = Double(seatAmount) ?? game.buyIn
                        if seatPick == "__new" || seatPick.isEmpty && notSeated.isEmpty { sheet = .newPlayer(seatAmount: amt) }
                        else { confirmBuy = (seatPick.isEmpty ? notSeated[0].id : seatPick, amt) }
                    }
                    .buttonStyle(PillButtonStyle(primary: true))
                }
                .onAppear { if seatPick.isEmpty { seatPick = notSeated.first?.id ?? "__new" } }
                .onChange(of: notSeated.map(\.id)) { _, ids in if !ids.contains(seatPick) { seatPick = ids.first ?? "__new" } }

                BigChips(game: game)
            }

            if amounts && s.cashouts > 0 { SettleView(ledger: ledger, game: game, final: false) }

            if club.canEdit {
                HStack {
                    Button("Delete game", role: .destructive) { confirmDelete = true }.font(.app(14)).foregroundStyle(Theme.neg)
                    Spacer()
                    Button("Settle & close") { sheet = .close }.buttonStyle(PillButtonStyle())
                }
                .padding(.top, 4)
            }
        }
        .cardSurface()
        .confirmationDialog("Delete \(game.name)? Everything recorded in it comes off the pot, the jackpot and the standings.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete game", role: .destructive) {
                club.updateGame(game.id, ["status": "deleted", "deletedAt": ClubStore.now], toast: "\(game.name) deleted")
            }
        }
    }
}

/// $25 / $50 / $100 chips on the table, so the host knows what to collect back.
private struct BigChips: View {
    @Environment(ClubStore.self) private var club
    let game: Game
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Big chips on the table").font(.app(14, .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Text(Money.format(Ledger.bigChipsTotal(game))).font(.app(14, .bold)).monospacedDigit().foregroundStyle(Theme.text)
            }
            ForEach(Ledger.chipDenominations, id: \.self) { d in
                let n = game.bigChips[String(d)] ?? 0
                HStack {
                    Circle().fill(d == 25 ? Theme.accent : d == 50 ? Color(hex: 0xE89A5B) : Color(hex: 0xE4E4E7)).frame(width: 12, height: 12)
                    Text("$\(d)").font(.app(14)).foregroundStyle(Theme.text)
                    Spacer()
                    RoundIconButton(symbol: "minus", label: "One less $\(d) chip") { set(d, n - 1) }.disabled(n <= 0)
                    Text("\(n)").font(.app(15, .bold)).monospacedDigit().frame(minWidth: 24)
                    RoundIconButton(symbol: "plus", label: "One more $\(d) chip") { set(d, n + 1) }
                }
            }
        }
        .padding(.top, 6)
    }
    private func set(_ d: Int, _ n: Int) {
        var c = game.bigChips
        c[String(d)] = max(0, n)
        club.updateGame(game.id, ["bigChips": c])
    }
}

/// Who gets what. Collect before: what the pot pays each player. Collect after: who pays who.
struct SettleView: View {
    let ledger: Ledger
    let game: Game
    let final: Bool

    var body: some View {
        let s = ledger.summary(game.id)
        let left = s.buy - s.drop - s.hh - s.out
        let pending = s.seats.filter { !$0.seat.isCashedOut }.count
        VStack(alignment: .leading, spacing: 6) {
            Text(game.collectAfter ? "Who pays who" : "Owed from the pot").font(.app(15, .bold)).foregroundStyle(Theme.text)
            if game.collectAfter {
                let t = ledger.settleTransfers(game.id)
                if t.isEmpty { Text("Nothing to settle yet").font(.app(13)).foregroundStyle(Theme.text2) }
                ForEach(Array(t.enumerated()), id: \.offset) { _, x in
                    HStack { Text("\(x.from) → \(x.to)").font(.app(14)).foregroundStyle(Theme.text); Spacer(); Text(Money.format(x.amount)).font(.app(14, .bold)).monospacedDigit() }
                }
            } else {
                ForEach(s.seats.filter { $0.seat.isCashedOut }.sorted { $0.seat.cashOut > $1.seat.cashOut }) { x in
                    let pid = x.playerId, seat = x.seat
                    HStack {
                        Text(ledger.name(pid)).font(.app(14, .semibold)).foregroundStyle(Theme.text)
                        Text(Money.format(seat.net, signed: true)).font(.app(12)).foregroundStyle(Theme.result(seat.net))
                        Spacer()
                        Text(Money.format(seat.cashOut)).font(.app(14, .bold)).monospacedDigit().foregroundStyle(Theme.text)
                    }
                }
                Text("Collected \(Money.format(s.buy)) · pays out \(Money.format(s.out))" + (s.drop > 0 ? " · \(Money.format(s.drop)) to the jackpot" : "") + (s.hh > 0 ? " · \(Money.format(s.hh)) to the high hand" : ""))
                    .font(.app(12)).foregroundStyle(Theme.text2)
            }
            if !final && pending > 0 { Text("\(pending) not cashed out yet (counted as $0)").font(.app(12)).foregroundStyle(Theme.text2) }
            if abs(left) >= 0.005 {
                Text(left > 0 ? "\(Money.format(left)) of buy-ins isn't in the cash-outs. Check chip counts." : "Cash-outs are \(Money.format(-left)) more than was bought in.")
                    .font(.app(13)).foregroundStyle(Theme.neg)
            }
        }
        .padding(.top, 6)
    }
}

private struct JackpotCard: View {
    @Environment(ClubStore.self) private var club
    let ledger: Ledger
    let game: Game
    @Binding var sheet: GameSheet?

    var body: some View {
        let jp = ledger.jackpot
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bad beat jackpot").font(.app(18, .bold)).foregroundStyle(Theme.text)
                Spacer()
                Text(Money.format(jp.balance)).font(.app(18, .bold)).monospacedDigit().foregroundStyle(Theme.text)
            }
            if club.canEdit {
                FlowRow {
                    Button("+\(Money.format(game.drop)) drop") {
                        club.addEntry(["gameId": game.id, "kind": "drop", "amount": game.drop, "hands": 1])
                    }.buttonStyle(PillButtonStyle(primary: true))
                    Button("Several hands…") { sheet = .drops(highHand: false) }.buttonStyle(PillButtonStyle())
                    Button("Bad beat hit…") { sheet = .hit }.buttonStyle(PillButtonStyle()).disabled(jp.balance <= 0)
                    Button("Manual payout…") { sheet = .payout }.buttonStyle(PillButtonStyle()).disabled(jp.balance <= 0)
                    Button("Adjust") { sheet = .adjustJackpot }.buttonStyle(PillButtonStyle())
                }
            }
        }
        .cardSurface()
    }
}

private struct HighHandCard: View {
    @Environment(ClubStore.self) private var club
    let ledger: Ledger
    let game: Game
    @Binding var sheet: GameSheet?
    @State private var alerted: Double?

    var body: some View {
        let h = ledger.highHand(game.id), pool = ledger.highHandPool, prize = game.hhPrize
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("High hand").font(.app(18, .bold)).foregroundStyle(Theme.text)
                Spacer()
                Text(prize > 0 ? "\(Money.format(prize)) prize" : Money.format(pool.balance)).font(.app(18, .bold)).monospacedDigit().foregroundStyle(Theme.text)
            }
            if game.hhTimer > 0 {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = Ledger.highHandTimeLeft(game, now: ctx.date)
                    HStack {
                        Text(left == nil ? "Timer · \(game.hhTimer) min" : "Next payout in").font(.app(13)).foregroundStyle(Theme.text2)
                        Spacer()
                        Text(left.map { $0 > 0 ? Self.clock($0) : "Time's up" } ?? "Not started")
                            .font(.app(24, .bold)).monospacedDigit().foregroundStyle((left ?? 1) <= 0 ? Theme.neg : Theme.text)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: (left ?? 1) <= 0) { _, up in
                        if up, club.canEdit, alerted != game.hhTimerStart {
                            alerted = game.hhTimerStart
                            club.message = "High hand timer is up. Pay the high hand."
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        }
                    }
                }
            }
            if let h {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hand to beat").font(.app(12)).foregroundStyle(Theme.text2)
                    Text(ledger.name(h.playerId)).font(.app(18, .semibold)).foregroundStyle(Theme.text)
                    Text(Ledger.handText(h)).font(.app(14)).foregroundStyle(Theme.text)
                }
            } else {
                Text("No high hand yet").font(.app(14)).foregroundStyle(Theme.text2)
            }
            if club.canEdit {
                FlowRow {
                    Button(h == nil ? "Record high hand…" : "New high hand…") { sheet = .recordHigh }.buttonStyle(PillButtonStyle(primary: true))
                    Button("Pay high hand…") { sheet = .payHigh }.buttonStyle(PillButtonStyle()).disabled(h == nil || (prize <= 0 && pool.balance <= 0))
                    if prize <= 0 && game.hhDrop > 0 {
                        Button("+\(Money.format(game.hhDrop)) drop") {
                            club.addEntry(["gameId": game.id, "kind": "hhdrop", "amount": game.hhDrop, "hands": 1])
                        }.buttonStyle(PillButtonStyle())
                        Button("Several hands…") { sheet = .drops(highHand: true) }.buttonStyle(PillButtonStyle())
                    }
                    if game.hhTimer > 0 {
                        Button(game.hhTimerStart == nil ? "Start timer" : "Restart timer") {
                            club.updateGame(game.id, ["hhTimerStart": ClubStore.now], toast: "High hand timer started · \(game.hhTimer) min")
                        }.buttonStyle(PillButtonStyle())
                    }
                    Button("Settings") { sheet = .highSettings }.buttonStyle(PillButtonStyle())
                }
            }
        }
        .cardSurface()
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up)), h = s / 3600, m = (s / 60) % 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

private struct LogCard: View {
    @Environment(ClubStore.self) private var club
    let ledger: Ledger
    let game: Game
    private static let time: DateFormatter = { let f = DateFormatter(); f.timeStyle = .short; return f }()

    var body: some View {
        let items = ledger.entries.filter { $0.gameId == game.id || (($0.kind == .jackpot || $0.kind == .jpadjust) && $0.ts >= game.createdAt) }
            .sorted { $0.ts > $1.ts }.prefix(80)
        VStack(alignment: .leading, spacing: 8) {
            Text("Cashier log").font(.app(18, .bold)).foregroundStyle(Theme.text)
            if items.isEmpty { Text("Nothing yet").font(.app(14)).foregroundStyle(Theme.text2) }
            ForEach(Array(items)) { e in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Self.time.string(from: Date(timeIntervalSince1970: e.ts / 1000))).font(.app(12)).foregroundStyle(Theme.text2).frame(width: 64, alignment: .leading)
                    Text(describe(e)).font(.app(14)).foregroundStyle(Theme.text)
                    Spacer(minLength: 0)
                    if club.canEdit {
                        Button { club.removeEntry(e.id) } label: { Image(systemName: "arrow.uturn.backward") }
                            .foregroundStyle(Theme.text2).accessibilityLabel("Undo")
                    }
                }
            }
        }
        .cardSurface()
    }

    private func describe(_ e: Entry) -> String {
        let n = ledger.name(e.playerId), a = Money.format(abs(e.amount))
        switch e.kind {
        case .buyin: return e.amount < 0 ? "\(n) buy-in reduced by \(a)" : "\(n) bought in \(a)"
        case .cashout: return "\(n) cashed out \(a)"
        case .drop: return "Jackpot drop \(a)" + ((e.hands ?? 1) > 1 ? " (\(e.hands!) hands)" : "")
        case .jackpot: return "\(n) paid \(a) from the jackpot" + (e.note.map { " · \($0)" } ?? "")
        case .jpadjust: return "Jackpot adjusted \(Money.format(e.amount, signed: true))"
        case .highhand: return "\(n) took the high hand · \(Ledger.handText(e))"
        case .hhdrop: return "High hand drop \(a)" + ((e.hands ?? 1) > 1 ? " (\(e.hands!) hands)" : "")
        case .hhpay: return "\(n) paid \(a) for the high hand"
        default: return e.kind.rawValue
        }
    }
}

/// Lays buttons out left to right and wraps onto new lines.
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0 && x + z.width > w { x = 0; y += row + spacing; row = 0 }
            x += z.width + spacing; row = max(row, z.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(maxX, w), height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + z.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z))
            x += z.width + spacing; row = max(row, z.height)
        }
    }
}
