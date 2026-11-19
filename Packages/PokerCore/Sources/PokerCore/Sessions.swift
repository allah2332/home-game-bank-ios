import Foundation

/// One personal session. The field names match the web app's backup file, so a backup made in
/// the web app restores on the iPhone and the other way round.
public struct Session: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var ts: Double
    public var type: String      // "cash" or "tourney"
    public var date: String      // yyyy-MM-dd, the day the session started
    public var start: String     // HH:mm, may be empty for old records
    public var end: String
    public var mins: Int
    public var game: String
    public var loc: String
    public var buy: Double
    public var out: Double
    public var tips: Double

    public init(id: String = Session.newID(), ts: Double = Date().timeIntervalSince1970 * 1000, type: String = "cash",
                date: String, start: String = "", end: String = "", mins: Int, game: String = "", loc: String = "",
                buy: Double, out: Double, tips: Double = 0) {
        self.id = id; self.ts = ts; self.type = type; self.date = date; self.start = start; self.end = end
        self.mins = mins; self.game = game; self.loc = loc; self.buy = buy; self.out = out; self.tips = tips
    }

    public var profit: Double { out - buy }
    public var isTourney: Bool { type == "tourney" }

    public static func newID() -> String { "s" + String(UInt64(Date().timeIntervalSince1970 * 1000), radix: 36) + String(UInt32.random(in: 0...UInt32.max), radix: 36) }

    enum CodingKeys: String, CodingKey { case id, ts, type, date, start, end, mins, game, loc, buy, out, tips }

    // Lenient: missing or odd fields fall back to defaults instead of failing the whole backup.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        date = try c.decode(String.self, forKey: .date)
        ts = (try? c.decodeIfPresent(Double.self, forKey: .ts)) ?? 0
        type = ((try? c.decodeIfPresent(String.self, forKey: .type)) ?? "cash") == "tourney" ? "tourney" : "cash"
        start = (try? c.decodeIfPresent(String.self, forKey: .start)) ?? ""
        end = (try? c.decodeIfPresent(String.self, forKey: .end)) ?? ""
        mins = max(0, Int((try? c.decodeIfPresent(Double.self, forKey: .mins)) ?? 0))
        game = String(((try? c.decodeIfPresent(String.self, forKey: .game)) ?? "").prefix(40))
        loc = String(((try? c.decodeIfPresent(String.self, forKey: .loc)) ?? "").prefix(40))
        buy = max(0, (try? c.decodeIfPresent(Double.self, forKey: .buy)) ?? 0)
        out = max(0, (try? c.decodeIfPresent(Double.self, forKey: .out)) ?? 0)
        tips = max(0, (try? c.decodeIfPresent(Double.self, forKey: .tips)) ?? 0)
    }
}

/// The backup file: {"app":"home-game-bank","kind":"sessions","v":1,"start":0,"sessions":[…]}.
public struct SessionBackup: Codable, Sendable {
    public var app = "home-game-bank"
    public var kind = "sessions"
    public var v = 1
    public var start: Double
    public var sessions: [Session]
    public init(start: Double, sessions: [Session]) { self.start = start; self.sessions = sessions }

    /// Accepts the backup object or a bare array of sessions. Records without a valid date are dropped.
    public static func decode(_ data: Data) throws -> SessionBackup {
        let dec = JSONDecoder()
        if let b = try? dec.decode(SessionBackup.self, from: data) { return SessionBackup(start: b.start, sessions: b.sessions.filter { SessionStats.day($0.date) != nil }) }
        let list = try dec.decode([Session].self, from: data)
        return SessionBackup(start: 0, sessions: list.filter { SessionStats.day($0.date) != nil })
    }

    enum CodingKeys: String, CodingKey { case app, kind, v, start, sessions }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = (try? c.decodeIfPresent(Double.self, forKey: .start)) ?? 0
        sessions = try c.decode([Session].self, forKey: .sessions)
    }
}

public enum SessionStats {
    public enum Grouping: String, CaseIterable, Sendable { case location = "Location", game = "Game", weekday = "Weekday", month = "Month" }

    public struct Summary: Equatable, Sendable {
        public var profit: Double, minutes: Int, tips: Double, count: Int, wins: Int, tourneys: Int, cashed: Int
        public var perHour: Double? { minutes > 0 ? profit / (Double(minutes) / 60) : nil }
        public var perSession: Double? { count > 0 ? profit / Double(count) : nil }
    }

    public struct Group: Identifiable, Equatable, Sendable {
        public var id: String
        public var label: String
        public var profit: Double
        public var minutes: Int
        public var count: Int
        public var hours: Int { Int((Double(minutes) / 60).rounded()) }
    }

    public struct Point: Identifiable, Equatable, Sendable {
        public var id: Int { index }
        public var index: Int
        public var date: String
        public var total: Double
        public var profit: Double
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()

    /// Noon on that day, so time zones never push it onto a different date.
    public static func day(_ s: String) -> Date? {
        guard s.count == 10 else { return nil }
        return dayFormatter.date(from: s + "T12:00")
    }

    public static func dateString(_ d: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func timeString(_ d: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Minutes from start to end ("HH:mm"); an end at or before the start means it ran past midnight.
    public static func spanMinutes(start: String, end: String) -> Int {
        func m(_ t: String) -> Int? {
            let p = t.split(separator: ":").compactMap { Int($0) }
            return p.count == 2 ? p[0] * 60 + p[1] : nil
        }
        guard let a = m(start), let b = m(end) else { return 0 }
        return (b - a + 1440) % 1440
    }

    public static func duration(_ mins: Int) -> String {
        let h = mins / 60, m = mins % 60
        return m > 0 ? "\(h) h \(m) m" : "\(h) h"
    }

    public static func summary(_ list: [Session]) -> Summary {
        let t = list.filter(\.isTourney)
        return Summary(profit: list.reduce(0) { $0 + $1.profit },
                       minutes: list.reduce(0) { $0 + $1.mins },
                       tips: list.reduce(0) { $0 + $1.tips },
                       count: list.count,
                       wins: list.filter { $0.profit > 0 }.count,
                       tourneys: t.count,
                       cashed: t.filter { $0.out > 0 }.count)
    }

    public static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    public static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    /// Location and game: best first. Weekday: Sunday to Saturday. Month: oldest first.
    public static func groups(_ list: [Session], by g: Grouping) -> [Group] {
        let cal = Calendar(identifier: .gregorian)
        func key(_ s: Session) -> String {
            switch g {
            case .location: return s.loc.isEmpty ? "—" : s.loc
            case .game: return s.game.isEmpty ? "—" : s.game
            case .weekday: return String(cal.component(.weekday, from: day(s.date) ?? Date()) - 1)
            case .month: return String(s.date.prefix(7))
            }
        }
        var map: [String: Group] = [:]
        var order: [String] = []
        for s in list {
            let k = key(s)
            if map[k] == nil { map[k] = Group(id: k, label: k, profit: 0, minutes: 0, count: 0); order.append(k) }
            map[k]!.profit += s.profit
            map[k]!.minutes += s.mins
            map[k]!.count += 1
        }
        var rows = order.compactMap { map[$0] }
        let years = Set(list.map { $0.date.prefix(4) }).count > 1
        switch g {
        case .weekday:
            rows.sort { (Int($0.id) ?? 0) < (Int($1.id) ?? 0) }
            for i in rows.indices { rows[i].label = weekdays[Int(rows[i].id) ?? 0] }
        case .month:
            rows.sort { $0.id < $1.id }
            for i in rows.indices {
                let parts = rows[i].id.split(separator: "-")
                let m = parts.count == 2 ? (Int(parts[1]) ?? 1) - 1 : 0
                let name = months[max(0, min(11, m))]
                rows[i].label = years ? "\(name.prefix(3)) \(parts.first ?? "")" : name
            }
        default:
            rows.sort { $0.profit > $1.profit }
        }
        return rows
    }

    /// Running total after each session, oldest first.
    public static func cumulative(_ list: [Session]) -> [Point] {
        let sorted = list.sorted { $0.date != $1.date ? $0.date < $1.date : $0.ts < $1.ts }
        var t = 0.0
        return sorted.enumerated().map { i, s in
            t += s.profit
            return Point(index: i, date: s.date, total: t, profit: s.profit)
        }
    }
}
