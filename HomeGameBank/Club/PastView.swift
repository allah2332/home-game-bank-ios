import SwiftUI
import PokerCore

/// Past games: every settled game with its totals; tap one for the payouts.
struct PastView: View {
    @Environment(ClubStore.self) private var club
    @State private var showing: Game?
    @State private var deleting: Game?

    var body: some View {
        let l = club.ledger
        ScrollView {
            VStack(spacing: 12) {
                ClubHeader()
                if club.sees(.board) {
                    StatCard(title: "All-time buy-ins", value: Money.format(l.allTimeBuyIns),
                             foot: "\(l.closedGames.count) settled game\(l.closedGames.count == 1 ? "" : "s") · \(l.players.count) players")
                    BoardCard(ledger: l)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Past games").font(.app(18, .bold)).foregroundStyle(Theme.text)
                        Spacer()
                        Text("\(l.closedGames.count) settled").font(.app(13)).foregroundStyle(Theme.text2)
                    }
                    if l.closedGames.isEmpty { Text("No settled games yet").font(.app(14)).foregroundStyle(Theme.text2) }
                    ForEach(l.closedGames) { g in
                        let s = l.summary(g.id)
                        let top = s.seats.max { $0.seat.net < $1.seat.net }
                        Button { showing = g } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(g.name).font(.app(16, .semibold)).foregroundStyle(Theme.text)
                                    Text(Date(timeIntervalSince1970: g.createdAt / 1000).formatted(date: .abbreviated, time: .omitted)
                                         + " · \(s.seats.count) players · \(Money.format(s.buy)) in").font(.app(12)).foregroundStyle(Theme.text2)
                                    if l.settings.hh, let h = l.nightHigh(g.id) {
                                        Text("High hand: \(l.name(h.playerId)) · \(Ledger.handText(h))").font(.app(12)).foregroundStyle(Theme.text2)
                                    }
                                }
                                Spacer()
                                if let top, top.seat.net > 0 {
                                    VStack(alignment: .trailing, spacing: 0) {
                                        Text(l.name(top.playerId)).font(.app(13)).foregroundStyle(Theme.text2)
                                        Text(Money.format(top.seat.net, signed: true)).font(.app(15, .bold)).monospacedDigit().foregroundStyle(Theme.pos)
                                    }
                                }
                            }
                            .padding(.vertical, 6).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if club.canEdit { Button("Delete game", role: .destructive) { deleting = g } }
                        }
                    }
                }
                .cardSurface()
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $showing) { g in
            NavigationStack {
                ScrollView { SettleView(ledger: club.ledger, game: g, final: true).padding(16) }
                    .navigationTitle(g.name).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showing = nil } } }
            }
            .presentationBackground(Theme.surface)
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Delete \(deleting?.name ?? "")? It comes off the standings for everyone.",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete game", role: .destructive) {
                if let g = deleting { club.updateGame(g.id, ["status": "deleted", "deletedAt": ClubStore.now], toast: "\(g.name) deleted") }
                deleting = nil
            }
        }
    }
}
