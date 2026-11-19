import Foundation
import Observation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import PokerCore

/// A club the phone has opened before. `hostKey` is set when this phone is a host.
struct SavedClub: Codable, Hashable, Identifiable {
    var code: String
    var name: String
    var hostKey: String?
    var id: String { code }
    var fullCode: String { hostKey.map { "\(code)-\($0)" } ?? code }
}

/// The shared home game: live copies of the club's players, games and cashier log, plus every change
/// the host can make. Players' phones get the same data and the database refuses their writes.
@Observable
@MainActor
final class ClubStore {
    enum Phase: Equatable { case unavailable(String), starting, idle, opening, open }

    private(set) var phase: Phase = .starting
    private(set) var code: String?
    private(set) var name = ""
    private(set) var isHost = false
    private(set) var hostKey: String?
    private(set) var settings = ClubSettings()
    private(set) var players: [Player] = []
    private(set) var games: [Game] = []
    private(set) var entries: [Entry] = []
    private(set) var loaded = false
    private(set) var saved: [SavedClub] = []
    /// A host previewing the player view (typed the plain player code on a host phone).
    var previewAsPlayer = false
    var message: String?

    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    @ObservationIgnored private var db: Firestore?
    @ObservationIgnored private var uid: String?

    var ledger: Ledger { Ledger(players: players, games: games, entries: entries, settings: settings) }
    /// Host controls are shown. A host previewing as a player sees the player view.
    var canEdit: Bool { isHost && !previewAsPlayer }
    func sees(_ s: ClubSettings.Show) -> Bool { canEdit || settings.shows(s) }

    init() {
        saved = (UserDefaults.standard.data(forKey: "clubs").flatMap { try? JSONDecoder().decode([SavedClub].self, from: $0) }) ?? []
    }

    // MARK: start, open, leave

    func start() async {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            phase = .unavailable("Shared games aren't connected in this build yet.")
            return
        }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        db = Firestore.firestore()
        do {
            uid = try await Auth.auth().signInAnonymously().user.uid
            phase = .idle
            if let last = UserDefaults.standard.string(forKey: "lastClub"), let s = saved.first(where: { $0.code == last }) {
                await open(s.fullCode, typed: false)
            }
        } catch {
            phase = .unavailable("Couldn't connect. Check your internet connection and reopen the app.")
        }
    }

    static func split(_ raw: String) -> (code: String, key: String?) {
        let t = raw.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let parts = t.split(separator: "-").map(String.init)
        if parts.count == 3 { return ("\(parts[0])-\(parts[1])", parts[2]) }
        return (t, nil)
    }

    /// Opens a club from a typed or saved code. The full host code makes this phone a host.
    /// Typing the plain player code on a host phone shows the player view until "Host view" is tapped.
    func open(_ raw: String, typed: Bool) async {
        guard let db, let uid else { return }
        let (code, typedKey) = Self.split(raw)
        guard code.count >= 7 else { message = "That doesn't look like a game code."; return }
        phase = .opening
        do {
            let snap = try await db.collection("clubs").document(code).getDocument()
            guard snap.exists, let data = snap.data() else {
                phase = .idle; message = "No game found for \(code)."; forget(code); return
            }
            let savedKey = saved.first { $0.code == code }?.hostKey
            var host = (try? await db.collection("clubs").document(code).collection("hosts").document(uid).getDocument().exists) ?? false
            var key = host ? savedKey : nil
            if !host, let k = typedKey ?? savedKey {
                do {
                    try await db.collection("clubs").document(code).collection("hosts").document(uid).setData(["key": k, "at": Self.now])
                    host = true; key = k
                } catch {
                    if typedKey != nil { message = "That host code isn't right. Opened the player view." }
                }
            }
            if host, key == nil {
                key = try? await db.collection("clubs").document(code).collection("private").document("host").getDocument().data()?["key"] as? String
            }
            close()
            self.code = code
            name = data["name"] as? String ?? "Home game"
            settings = Self.decode(ClubSettings.self, data["settings"] as? [String: Any] ?? [:]) ?? ClubSettings()
            isHost = host
            hostKey = host ? key : nil
            previewAsPlayer = host && typed && typedKey == nil
            remember()
            listen()
            phase = .open
        } catch {
            phase = .idle
            message = "Couldn't reach the game. Check your connection and try again."
        }
    }

    /// Creates a club; this phone becomes its host.
    func create(name: String) async {
        guard let db, let uid else { return }
        phase = .opening
        let clean = name.trimmingCharacters(in: .whitespaces)
        for _ in 0..<5 {
            let code = Self.newCode()
            let ref = db.collection("clubs").document(code)
            if (try? await ref.getDocument().exists) == true { continue }
            let key = Self.randomChars(6)
            do {
                try await ref.setData(["name": clean.isEmpty ? "Home game" : String(clean.prefix(40)), "createdAt": Self.now, "owner": uid,
                                       "settings": ["bbj": false, "hh": false]])
                try await ref.collection("private").document("host").setData(["key": key])
                try await ref.collection("hosts").document(uid).setData(["key": key, "at": Self.now])
                saved.removeAll { $0.code == code }
                saved.insert(SavedClub(code: code, name: clean, hostKey: key), at: 0)
                await open("\(code)-\(key)", typed: false)
                message = "Created \(code). You're the host."
                return
            } catch {
                phase = .idle
                message = "Couldn't create the game. Check your connection and try again."
                return
            }
        }
        phase = .idle
    }

    func switchClub() {
        close()
        code = nil
        UserDefaults.standard.removeObject(forKey: "lastClub")
        phase = .idle
    }

    func forget(_ code: String) {
        saved.removeAll { $0.code == code }
        persistSaved()
    }

    private func close() {
        listeners.forEach { $0.remove() }
        listeners = []
        players = []; games = []; entries = []; loaded = false
    }

    private func remember() {
        guard let code else { return }
        saved.removeAll { $0.code == code }
        saved.insert(SavedClub(code: code, name: name, hostKey: hostKey), at: 0)
        saved = Array(saved.prefix(30))
        persistSaved()
        UserDefaults.standard.set(code, forKey: "lastClub")
    }

    private func persistSaved() {
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: "clubs")
    }

    private func listen() {
        guard let db, let code else { return }
        let club = db.collection("clubs").document(code)
        var got = Set<String>()
        func mark(_ k: String) { got.insert(k); if got.count == 4 { loaded = true } }
        listeners.append(club.addSnapshotListener { [weak self] snap, _ in
            guard let self, let d = snap?.data() else { return }
            self.name = d["name"] as? String ?? self.name
            self.settings = Self.decode(ClubSettings.self, d["settings"] as? [String: Any] ?? [:]) ?? ClubSettings()
            mark("club")
        })
        listeners.append(club.collection("players").addSnapshotListener { [weak self] snap, _ in
            guard let self, let snap else { return }
            self.players = snap.documents.compactMap { Self.decodeDoc(Player.self, $0) }
            mark("players")
        })
        listeners.append(club.collection("games").addSnapshotListener { [weak self] snap, _ in
            guard let self, let snap else { return }
            self.games = snap.documents.compactMap { Self.decodeDoc(Game.self, $0) }
            mark("games")
        })
        listeners.append(club.collection("entries").addSnapshotListener { [weak self] snap, _ in
            guard let self, let snap else { return }
            self.entries = snap.documents.compactMap { Self.decodeDoc(Entry.self, $0) }
            mark("entries")
        })
    }

    // MARK: writes (hosts only; the database refuses anyone else)

    private func club() -> DocumentReference? { code.flatMap { db?.collection("clubs").document($0) } }

    /// Writes go straight to the phone's local copy and sync in the background, so the screen updates at once.
    private func write(_ toast: String? = nil, _ op: @escaping (DocumentReference) async throws -> Void) {
        guard canEdit, let ref = club() else { message = "Only the host can change this game."; return }
        if let toast { message = toast }
        Task {
            do { try await op(ref) } catch {
                await MainActor.run { self.message = "Couldn't save that. Check your connection and try again." }
            }
        }
    }

    func addEntry(_ fields: [String: Any], toast: String? = nil) {
        var f = fields
        f["ts"] = f["ts"] ?? Self.now
        write(toast) { _ = try await $0.collection("entries").addDocument(data: f) }
    }

    func removeEntry(_ id: String) { write("Entry removed") { try await $0.collection("entries").document(id).delete() } }

    @discardableResult
    func addPlayer(_ name: String) -> String? {
        guard canEdit, let ref = club() else { return nil }
        let doc = ref.collection("players").document()
        let n = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
        players.append(Player(id: doc.documentID, name: n, createdAt: Self.now))
        write("\(n) added") { _ in try await doc.setData(["name": n, "createdAt": Self.now]) }
        return doc.documentID
    }

    func startGame(name: String, buyIn: Double, drop: Double, collectAfter: Bool, hhDrop: Double, hhPrize: Double, hhTimer: Int) {
        let now = Self.now
        write("Game started. Shuffle up and deal.") {
            _ = try await $0.collection("games").addDocument(data: [
                "name": name, "status": "open", "createdAt": now, "buyIn": buyIn, "drop": drop,
                "collect": collectAfter ? "after" : "before", "hhDrop": hhDrop, "hhPrize": hhPrize, "hhTimer": hhTimer,
                "hhTimerStart": hhTimer > 0 ? now : NSNull(), "bigChips": [String: Int]()])
        }
    }

    func updateGame(_ id: String, _ fields: [String: Any], toast: String? = nil) {
        write(toast) { try await $0.collection("games").document(id).updateData(fields) }
    }

    func updateSettings(_ change: (inout ClubSettings) -> Void, toast: String? = nil) {
        var s = settings
        change(&s)
        settings = s
        let data: [String: Any] = ["bbj": s.bbj, "hh": s.hh, "split": ["loser": s.split.loser, "winner": s.split.winner, "table": s.split.table], "show": s.show]
        write(toast) { try await $0.updateData(["settings": data]) }
    }

    // MARK: helpers

    static var now: Double { (Date().timeIntervalSince1970 * 1000).rounded() }
    private static let words = ["ACES", "KINGS", "FLUSH", "RIVER", "TURN", "NUTS", "CHIPS", "ALLIN", "BLUFF", "DEUCE", "JACKS", "QUADS"]
    private static let chars = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    static func randomChars(_ n: Int) -> String { String((0..<n).map { _ in chars.randomElement()! }) }
    static func newCode() -> String { "\(words.randomElement()!)-\(randomChars(5))" }

    static func decode<T: Decodable>(_ t: T.Type, _ dict: [String: Any]) -> T? {
        guard JSONSerialization.isValidJSONObject(dict), let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(t, from: data)
    }

    private static func decodeDoc<T: Decodable & Identifiable>(_ t: T.Type, _ doc: QueryDocumentSnapshot) -> T? where T.ID == String {
        var d = doc.data()
        d["id"] = doc.documentID
        for (k, v) in d where v is NSNull { d.removeValue(forKey: k) }
        return decode(t, d)
    }
}
