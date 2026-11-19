import SwiftUI

@main
struct HomeGameBankApp: App {
    @State private var stats = StatsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(stats)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onAppear { if LaunchOptions.demo { stats.seedDemoIfEmpty() } }
        }
    }
}

/// Launch arguments used by the build server to open a screen with sample data and take screenshots.
enum LaunchOptions {
    static let args = ProcessInfo.processInfo.arguments
    static var demo: Bool { args.contains("-demo") }
    static var tab: AppTab {
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count, let t = AppTab(rawValue: args[i + 1]) { return t }
        return .odds
    }
}
