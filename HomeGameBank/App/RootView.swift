import SwiftUI

enum AppTab: String, CaseIterable {
    case home, odds, game, stats, past

    var title: String {
        switch self {
        case .home: return "Home"
        case .odds: return "Odds"
        case .game: return "Current game"
        case .stats: return "My stats"
        case .past: return "Past games"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house"
        case .odds: return "percent"
        case .game: return "suit.spade.fill"
        case .stats: return "chart.line.uptrend.xyaxis"
        case .past: return "trophy"
        }
    }
}

struct RootView: View {
    @Environment(ClubStore.self) private var club
    @State private var tab: AppTab = LaunchOptions.tab

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .odds: OddsView()
                case .stats: StatsView()
                case .home, .game, .past:
                    if club.phase != .open {
                        JoinView()
                    } else if tab == .home {
                        HomeView(openGameTab: { tab = .game })
                    } else if tab == .game {
                        GameView()
                    } else if club.sees(.past) {
                        PastView()
                    } else {
                        HomeView(openGameTab: { tab = .game })
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            TabBar(tab: $tab, showPast: club.phase != .open || club.sees(.past), live: club.phase == .open && club.ledger.openGame != nil)
        }
        .background(Theme.bg.ignoresSafeArea())
        .overlay(alignment: .bottom) { Toast() }
        .task { await club.start() }
    }
}

/// Short message above the tab bar (saved, refused, connection problems).
private struct Toast: View {
    @Environment(ClubStore.self) private var club
    var body: some View {
        if let m = club.message {
            Text(m).font(.app(14, .medium)).foregroundStyle(Theme.bg)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Theme.text, in: Capsule())
                .padding(.bottom, 84).padding(.horizontal, 16)
                .transition(.opacity)
                .task(id: m) {
                    try? await Task.sleep(for: .seconds(2.6))
                    if club.message == m { club.message = nil }
                }
        }
    }
}

/// Bottom bar like the web app: four tabs and a round spade button in the middle for the current game.
struct TabBar: View {
    @Binding var tab: AppTab
    var showPast = true
    var live = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { t in
                if t != .past || showPast {
                    Button { tab = t } label: {
                        if t == .game {
                            Image(systemName: t.icon).font(.system(size: 22, weight: .semibold))
                                .frame(width: 52, height: 52)
                                .foregroundStyle(tab == t ? Theme.onAccent : Theme.text)
                                .background(tab == t ? Theme.accent : Theme.fill, in: Circle())
                                .overlay(alignment: .topTrailing) {
                                    if live { Circle().fill(Theme.accent).frame(width: 10, height: 10).overlay(Circle().stroke(Theme.surface, lineWidth: 2)) }
                                }
                                .offset(y: -6)
                        } else {
                            VStack(spacing: 3) {
                                Image(systemName: t.icon).font(.system(size: 20, weight: .medium)).frame(height: 24)
                                Text(t.title).font(.app(11, tab == t ? .bold : .medium)).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .foregroundStyle(tab == t ? Theme.accent : Theme.text2)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .accessibilityLabel(t.title)
                    .accessibilityAddTraits(tab == t ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 6).padding(.top, 4)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}
