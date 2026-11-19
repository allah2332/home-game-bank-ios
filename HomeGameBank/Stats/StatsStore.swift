import Foundation
import Observation
import PokerCore

/// Personal sessions, saved as a JSON file in the app's Documents folder on this phone
/// (included in the phone's iCloud/iTunes backup). Same format as the web app's backup file.
@Observable
final class StatsStore {
    private(set) var sessions: [Session] = []
    private(set) var startBankroll: Double = 0

    func setStartBankroll(_ v: Double) { startBankroll = v; save() }

    @ObservationIgnored private let url: URL

    init(fileName: String = "sessions.json") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = dir.appendingPathComponent(fileName)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url), let b = try? SessionBackup.decode(data) else { return }
        sessions = b.sessions
        startBankroll = b.start
    }

    private func save() {
        if let data = try? JSONEncoder().encode(SessionBackup(start: startBankroll, sessions: sessions)) {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    func upsert(_ s: Session) {
        if let i = sessions.firstIndex(where: { $0.id == s.id }) { sessions[i] = s } else { sessions.append(s) }
        save()
    }

    func delete(id: String) {
        sessions.removeAll { $0.id == id }
        save()
    }

    /// Writes a backup file to share (Files, AirDrop, email) and returns where it is.
    func backupFile() -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("poker-sessions-\(SessionStats.dateString(Date())).json")
        if let data = try? JSONEncoder().encode(SessionBackup(start: startBankroll, sessions: sessions)) { try? data.write(to: file, options: .atomic) }
        return file
    }

    /// Merges a backup (from this app or the web app) by session id. Returns (sessions in file, new ones).
    func restore(from file: URL) throws -> (Int, Int) {
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        let b = try SessionBackup.decode(Data(contentsOf: file))
        var byID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        var added = 0
        for s in b.sessions {
            if byID[s.id] == nil { added += 1 }
            byID[s.id] = s
        }
        sessions = Array(byID.values)
        if startBankroll == 0 && b.start != 0 { startBankroll = b.start }
        save()
        return (b.sessions.count, added)
    }

    /// Sample sessions for screenshots on the build server (only when there are none).
    func seedDemoIfEmpty() {
        guard sessions.isEmpty else { return }
        let rows: [(String, String, String, String, String, Double, Double, Double, Bool)] = [
            ("2026-07-10", "20:00", "00:00", "NL Texas Holdem", "SIENA", 300, 800, 0, false),
            ("2026-08-03", "19:00", "00:30", "NL Texas Holdem", "Gian", 500, 200, 20, false),
            ("2026-09-15", "21:00", "00:00", "NL Omaha", "SIENA", 700, 0, 0, false),
            ("2026-10-21", "18:00", "00:00", "NL Texas Holdem", "Office", 200, 900, 15, false),
            ("2026-11-12", "12:00", "14:00", "Deepstack", "WPT", 150, 0, 0, true),
            ("2026-11-16", "12:00", "17:00", "Deepstack", "WPT", 150, 600, 0, true),
        ]
        for (i, r) in rows.enumerated() {
            sessions.append(Session(id: "demo\(i)", ts: Double(i), type: r.8 ? "tourney" : "cash", date: r.0, start: r.1, end: r.2,
                                    mins: SessionStats.spanMinutes(start: r.1, end: r.2), game: r.3, loc: r.4, buy: r.5, out: r.6, tips: r.7))
        }
        save()
    }
}
