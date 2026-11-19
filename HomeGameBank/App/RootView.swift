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
    @State private var tab: AppTab = LaunchOptions.tab

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .odds: OddsView()
                case .stats: StatsView()
                case .home, .game, .past: SharedGamesComingView(tab: tab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            TabBar(tab: $tab)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

/// Bottom bar like the web app: four tabs and a round spade button in the middle for the current game.
struct TabBar: View {
    @Binding var tab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    if t == .game {
                        Image(systemName: t.icon).font(.system(size: 22, weight: .semibold))
                            .frame(width: 52, height: 52)
                            .foregroundStyle(tab == t ? Theme.onAccent : Theme.text)
                            .background(tab == t ? Theme.accent : Theme.fill, in: Circle())
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
        .padding(.horizontal, 6).padding(.top, 4)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

/// Placeholder for the tabs that need the shared online database, which is the next milestone.
struct SharedGamesComingView: View {
    let tab: AppTab
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: tab.icon).font(.system(size: 40)).foregroundStyle(Theme.accent)
            Text(tab.title).font(.app(22, .bold)).foregroundStyle(Theme.text)
            Text("Shared games are being moved over next.").font(.app(15)).foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
