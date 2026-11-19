import SwiftUI
import PokerCore

/// Shown on the shared-game tabs until a club is open: enter a code, create a game, or pick a saved one.
struct JoinView: View {
    @Environment(ClubStore.self) private var club
    @State private var code = ""
    @State private var newName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch club.phase {
                case .unavailable(let why):
                    Text(why).font(.app(15)).foregroundStyle(Theme.text2)
                case .starting, .opening:
                    HStack { ProgressView(); Text("Connecting…").foregroundStyle(Theme.text2) }
                default:
                    Text("Enter your game code").font(.app(22, .bold)).foregroundStyle(Theme.text)
                    HStack {
                        TextField("ACES-7K2QM", text: $code)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .font(.app(18, .semibold)).monospaced()
                            .padding(.horizontal, 14).frame(height: 46)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12))
                            .onSubmit { join() }
                        Button("Open") { join() }.buttonStyle(PillButtonStyle(primary: true)).disabled(code.count < 7)
                    }
                    if !club.saved.isEmpty {
                        Text("Your games").font(.app(15, .bold)).foregroundStyle(Theme.text).padding(.top, 6)
                        ForEach(club.saved) { s in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.name.isEmpty ? "Home game" : s.name).font(.app(16, .semibold)).foregroundStyle(Theme.text)
                                    Text(s.code + (s.hostKey != nil ? " · Host" : "")).font(.app(13)).monospaced().foregroundStyle(Theme.text2)
                                }
                                Spacer()
                                Button("Open") { Task { await club.open(s.fullCode, typed: false) } }.buttonStyle(PillButtonStyle())
                            }
                            .padding(.vertical, 6)
                            .contextMenu { Button("Remove from this list", role: .destructive) { club.forget(s.code) } }
                        }
                    }
                    Divider().overlay(Theme.border).padding(.vertical, 6)
                    Text("Start a new game group").font(.app(15, .bold)).foregroundStyle(Theme.text)
                    HStack {
                        TextField("Group name", text: $newName)
                            .padding(.horizontal, 14).frame(height: 46)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12))
                        Button("Create") { Task { await club.create(name: newName) } }.buttonStyle(PillButtonStyle())
                    }
                }
            }
            .cardSurface()
            .padding(12)
        }
    }

    private func join() {
        let c = code
        Task { await club.open(c, typed: true) }
    }
}

/// Club name, role and player code across the top of the shared-game tabs.
struct ClubHeader: View {
    @Environment(ClubStore.self) private var club

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(club.name).font(.app(20, .bold)).foregroundStyle(Theme.text)
            HStack(spacing: 8) {
                Text(club.canEdit ? "Host" : "Player").font(.app(12, .semibold)).foregroundStyle(Theme.text2)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.fill, in: Capsule())
                if let code = club.code {
                    Text(code).font(.app(15, .bold)).monospaced().foregroundStyle(Theme.text)
                    ShareLink(item: code) { Image(systemName: "square.and.arrow.up") }.foregroundStyle(Theme.text2)
                }
                Spacer()
                if club.isHost && club.previewAsPlayer {
                    Button("Host view") { club.previewAsPlayer = false }.buttonStyle(PillButtonStyle(primary: true))
                }
                Button("Switch") { club.switchClub() }.font(.app(14)).foregroundStyle(Theme.text2)
            }
            if !club.loaded { Text("Loading…").font(.app(13)).foregroundStyle(Theme.text2) }
        }
        .cardSurface()
    }
}
