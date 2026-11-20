import SwiftUI
import PokerCore

/// Home: the player's own hub. Nothing here belongs to a game group.
struct DashboardView: View {
    @Environment(StatsStore.self) private var stats
    @Environment(ClubStore.self) private var club
    var go: (AppTab) -> Void
    @State private var adding = false

    var body: some View {
        let all = stats.sessions
        let sum = SessionStats.summary(all)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Home").font(.app(28, .bold)).foregroundStyle(Theme.text).padding(.horizontal, 4).padding(.top, 4)

                // My results at a glance
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("My results").font(.app(15, .semibold)).foregroundStyle(Theme.text2)
                        Spacer()
                        Button("See all") { go(.stats) }.font(.app(14, .medium)).foregroundStyle(Theme.accent)
                    }
                    if all.isEmpty {
                        Text("No sessions yet").font(.app(26, .bold)).foregroundStyle(Theme.text)
                    } else {
                        Text(Money.format(sum.profit, signed: true)).font(.app(36, .bold)).monospacedDigit().foregroundStyle(Theme.result(sum.profit))
                        Text("\(sum.count) session\(sum.count == 1 ? "" : "s") · \(SessionStats.duration(sum.minutes))" + (sum.perHour.map { " · \(Money.format($0, signed: true))/h" } ?? ""))
                            .font(.app(13)).foregroundStyle(Theme.text2)
                        if all.count >= 2 { ProfitChart(points: SessionStats.cumulative(all)) }
                    }
                }
                .cardSurface()

                // Tools
                VStack(spacing: 10) {
                    ToolButton(icon: "suit.spade.fill", title: "Run or join a game", detail: club.phase == .open ? "Open: \(club.name)" : "Buy-ins, pot, jackpot, high hand") { go(.game) }
                    ToolButton(icon: "percent", title: "Calculate odds", detail: "Hold'em and PLO equity") { go(.odds) }
                    ToolButton(icon: "plus.circle", title: "Add session", detail: "Log a result from any game") { adding = true }
                }

                if !club.saved.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("My game groups").font(.app(15, .semibold)).foregroundStyle(Theme.text2)
                        ForEach(club.saved.prefix(5)) { s in
                            Button {
                                Task { await club.open(s.fullCode, typed: false); go(.game) }
                            } label: {
                                HStack {
                                    Text(s.name.isEmpty ? "Home game" : s.name).font(.app(16, .semibold)).foregroundStyle(Theme.text)
                                    if s.hostKey != nil { Tag("Host") }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Theme.text2)
                                }
                                .padding(.vertical, 6).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .cardSurface()
                }
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $adding) { SessionEditor(original: nil) }
    }
}

private struct ToolButton: View {
    let icon: String, title: String, detail: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.onAccent)
                    .frame(width: 44, height: 44).background(Theme.accent, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.app(17, .semibold)).foregroundStyle(Theme.text)
                    Text(detail).font(.app(13)).foregroundStyle(Theme.text2).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.text2)
            }
            .cardSurface()
        }
        .buttonStyle(.plain)
    }
}
