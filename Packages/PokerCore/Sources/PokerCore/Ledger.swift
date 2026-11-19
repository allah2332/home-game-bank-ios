import Foundation

// The shared-game money rules, ported from the web app (gameSummary, jackpot, allTime, transfers,
// hitShares, high hand). Pure data in, numbers out, so it can be unit tested without a database.

public struct Player: Codable, Identifiable, Hashable, Sendable {
    public var id: String = ""
    public var name: String
    public var createdAt: Double = 0
    public init(id: String, name: String, createdAt: Double = 0) { self.id = id; self.name = name; self.createdAt = createdAt }
}

public struct Game: Codable, Identifiable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable { case open, closed, deleted }
    public var id: String = ""
    public var name: String
    public var status: Status = .open
    public var createdAt: Double = 0
    public var closedAt: Double?
    public var buyIn: Double = 20
    /// Bad beat jackpot drop per hand.
    public var drop: Double = 1
    /// "before": buy-ins go into the pot; "after": everyone settles up at the end.
    public var collect: String = "before"
    public var hhDrop: Double = 1
    public var hhPrize: Double = 0
    public var hhTimer: Int = 0
    public var hhTimerStart: Double?
    public var bigChips: [String: Int] = [:]

    public init(id: String, name: String, createdAt: Double = 0, buyIn: Double = 20, drop: Double = 1, collect: String = "before",
                hhDrop: Double = 1, hhPrize: Double = 0, hhTimer: Int = 0) {
        self.id = id; self.name = name; self.createdAt = createdAt; self.buyIn = buyIn; self.drop = drop; self.collect = collect
        self.hhDrop = hhDrop; self.hhPrize = hhPrize; self.hhTimer = hhTimer
    }

    public var collectAfter: Bool { collect == "after" }

    enum CodingKeys: String, CodingKey { case id, name, status, createdAt, closedAt, buyIn, drop, collect, hhDrop, hhPrize, hhTimer, hhTimerStart, bigChips }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Game"
        status = (try? c.decodeIfPresent(Status.self, forKey: .status)) ?? .open
        createdAt = (try? c.decodeIfPresent(Double.self, forKey: .createdAt)) ?? 0
        closedAt = try? c.decodeIfPresent(Double.self, forKey: .closedAt)
        buyIn = (try? c.decodeIfPresent(Double.self, forKey: .buyIn)) ?? 20
        drop = (try? c.decodeIfPresent(Double.self, forKey: .drop)) ?? 1
        collect = (try? c.decodeIfPresent(String.self, forKey: .collect)) ?? "before"
        hhDrop = (try? c.decodeIfPresent(Double.self, forKey: .hhDrop)) ?? 1
        hhPrize = (try? c.decodeIfPresent(Double.self, forKey: .hhPrize)) ?? 0
        hhTimer = Int((try? c.decodeIfPresent(Double.self, forKey: .hhTimer)) ?? 0)
        hhTimerStart = try? c.decodeIfPresent(Double.self, forKey: .hhTimerStart)
        bigChips = (try? c.decodeIfPresent([String: Int].self, forKey: .bigChips)) ?? [:]
    }
}

public struct Entry: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case buyin, cashout, drop, jackpot, jpadjust, adjust, highhand, hhdrop, hhpay, unknown
    }
    public var id: String = ""
    public var ts: Double
    public var gameId: String?
    public var playerId: String?
    public var kind: Kind
    public var amount: Double = 0
    public var hands: Int?
    public var note: String?
    /// Standings edits: buy-ins and games added to the all-time board.
    public var buyins: Double?
    public var games: Int?
    /// High hand category (0 three of a kind … 6 royal flush).
    public var rank: Int?
    /// A high hand prize paid by the house rather than from the drop pot.
    public var fixed: Bool?

    public init(id: String = "", ts: Double, gameId: String? = nil, playerId: String? = nil, kind: Kind, amount: Double = 0,
                hands: Int? = nil, note: String? = nil, buyins: Double? = nil, games: Int? = nil, rank: Int? = nil, fixed: Bool? = nil) {
        self.id = id; self.ts = ts; self.gameId = gameId; self.playerId = playerId; self.kind = kind; self.amount = amount
        self.hands = hands; self.note = note; self.buyins = buyins; self.games = games; self.rank = rank; self.fixed = fixed
    }

    enum CodingKeys: String, CodingKey { case id, ts, gameId, playerId, kind, amount, hands, note, buyins, games, rank, fixed }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        ts = (try? c.decodeIfPresent(Double.self, forKey: .ts)) ?? 0
        gameId = try? c.decodeIfPresent(String.self, forKey: .gameId)
        playerId = try? c.decodeIfPresent(String.self, forKey: .playerId)
        kind = Kind(rawValue: (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "") ?? .unknown
        amount = (try? c.decodeIfPresent(Double.self, forKey: .amount)) ?? 0
        hands = (try? c.decodeIfPresent(Double.self, forKey: .hands)).map { Int($0) }
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        buyins = try? c.decodeIfPresent(Double.self, forKey: .buyins)
        games = (try? c.decodeIfPresent(Double.self, forKey: .games)).map { Int($0) }
        rank = (try? c.decodeIfPresent(Double.self, forKey: .rank)).map { Int($0) }
        fixed = try? c.decodeIfPresent(Bool.self, forKey: .fixed)
    }
}

public struct JackpotSplit: Codable, Hashable, Sendable {
    public var loser: Double = 50, winner: Double = 25, table: Double = 25
    public init(loser: Double = 50, winner: Double = 25, table: Double = 25) { self.loser = loser; self.winner = winner; self.table = table }
    public var isValid: Bool { [loser, winner, table].allSatisfy { $0 >= 0 } && abs(loser + winner + table - 100) < 0.01 }
}

/// Club-wide switches, kept in the club document.
public struct ClubSettings: Codable, Hashable, Sendable {
    /// What players (not hosts) can see. Missing keys count as shown.
    public enum Show: String, CaseIterable, Sendable {
        case jackpot, highhand, board, amounts, pot, log, past
        public var label: String {
            switch self {
            case .jackpot: return "Bad beat jackpot"
            case .highhand: return "High hand"
            case .board: return "All-time leaderboard"
            case .amounts: return "Who's in for how much"
            case .pot: return "Live game pot"
            case .log: return "Cashier log"
            case .past: return "Past games"
            }
        }
    }
    public var bbj = false
    public var hh = false
    public var split = JackpotSplit()
    public var show: [String: Bool] = [:]
    public init() {}
    public func shows(_ s: Show) -> Bool { show[s.rawValue] != false }

    enum CodingKeys: String, CodingKey { case bbj, hh, split, show }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        bbj = (try? c.decodeIfPresent(Bool.self, forKey: .bbj)) ?? false
        hh = (try? c.decodeIfPresent(Bool.self, forKey: .hh)) ?? false
        let sp = (try? c.decodeIfPresent(JackpotSplit.self, forKey: .split)) ?? JackpotSplit()
        split = sp.isValid ? sp : JackpotSplit()
        show = (try? c.decodeIfPresent([String: Bool].self, forKey: .show)) ?? [:]
    }
}

public struct Ledger: Sendable {
    public struct Seat: Equatable, Sendable {
        public var buyIn: Double = 0, cashOut: Double = 0, buys = 0, cashed = 0
        public var net: Double { cashOut - buyIn }
        public var isCashedOut: Bool { cashed > 0 }
    }
    public struct SeatEntry: Identifiable, Equatable, Sendable {
        public var playerId: String
        public var seat: Seat
        public var id: String { playerId }
    }
    public struct GameSummary: Sendable {
        /// Seats in the order players first bought in.
        public var seats: [SeatEntry]
        public var drop: Double, hh: Double, buy: Double, out: Double
        public var onTable: Double { buy - out - drop - hh }
        public var cashouts: Int { seats.reduce(0) { $0 + $1.seat.cashed } }
        public func seat(_ id: String) -> Seat? { seats.first { $0.playerId == id }?.seat }
    }
    public struct Pool: Equatable, Sendable { public var balance: Double, hands: Int, last: Entry? }
    public struct BoardRow: Identifiable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var games: Int, buyIn: Double, net: Double, bbj: Double, hh: Double, best: Double?, edited: Bool
    }
    public struct Transfer: Equatable, Sendable { public var from: String, to: String, amount: Double }

    public var players: [String: Player]
    public var games: [Game]
    public var entries: [Entry]
    public var settings: ClubSettings

    /// Deleted games and everything recorded in them drop out of every total.
    public init(players: [Player], games: [Game], entries: [Entry], settings: ClubSettings = ClubSettings()) {
        self.players = Dictionary(players.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let gone = Set(games.filter { $0.status == .deleted }.map(\.id))
        self.games = games.filter { $0.status != .deleted }
        self.entries = entries.filter { e in e.gameId.map { !gone.contains($0) } ?? true }
        self.settings = settings
    }

    public func name(_ id: String?) -> String { id.flatMap { players[$0]?.name } ?? "Unknown player" }

    public var openGame: Game? { games.filter { $0.status == .open }.max { $0.createdAt < $1.createdAt } }
    public var closedGames: [Game] { games.filter { $0.status == .closed }.sorted { ($0.closedAt ?? $0.createdAt) > ($1.closedAt ?? $1.createdAt) } }

    public func summary(_ gameId: String) -> GameSummary {
        var order: [String] = [], map: [String: Seat] = [:]
        var drop = 0.0, hh = 0.0, buy = 0.0, out = 0.0
        for e in entries.sorted(by: { $0.ts < $1.ts }) where e.gameId == gameId {
            switch e.kind {
            case .drop: drop += e.amount; continue
            case .hhdrop: hh += e.amount; continue
            case .buyin, .cashout: break
            default: continue
            }
            guard let pid = e.playerId else { continue }
            if map[pid] == nil { map[pid] = Seat(); order.append(pid) }
            if e.kind == .buyin {
                map[pid]!.buyIn += e.amount
                map[pid]!.buys = max(0, map[pid]!.buys + (e.amount < 0 ? -1 : 1))
                buy += e.amount
            } else {
                map[pid]!.cashOut += e.amount
                map[pid]!.cashed += 1
                out += e.amount
            }
        }
        return GameSummary(seats: order.map { SeatEntry(playerId: $0, seat: map[$0]!) }, drop: drop, hh: hh, buy: buy, out: out)
    }

    public var jackpot: Pool {
        var bal = 0.0, hands = 0, last: Entry?
        for e in entries {
            switch e.kind {
            case .drop: bal += e.amount; hands += e.hands ?? 1
            case .jpadjust: bal += e.amount
            case .jackpot: bal -= e.amount; if last == nil || e.ts > last!.ts { last = e }
            default: break
            }
        }
        return Pool(balance: (bal * 100).rounded() / 100, hands: hands, last: last)
    }

    /// High hand drop pot. Prizes paid by the house (`fixed`) don't come out of it.
    public var highHandPool: Pool {
        var bal = 0.0, hands = 0, last: Entry?
        for e in entries {
            if e.kind == .hhdrop { bal += e.amount; hands += e.hands ?? 1 }
            if e.kind == .hhpay { if e.fixed != true { bal -= e.amount }; if last == nil || e.ts > last!.ts { last = e } }
        }
        return Pool(balance: (bal * 100).rounded() / 100, hands: hands, last: last)
    }

    /// The hand to beat: best since the last high hand payout in this game (same category: the newer one).
    public func highHand(_ gameId: String) -> Entry? {
        var best: Entry?
        for e in entries.filter({ $0.gameId == gameId && ($0.kind == .highhand || $0.kind == .hhpay) }).sorted(by: { $0.ts < $1.ts }) {
            if e.kind == .hhpay { best = nil; continue }
            if best == nil || (e.rank ?? -1) >= (best!.rank ?? -1) { best = e }
        }
        return best
    }

    /// Best hand of the whole night, for past games.
    public func nightHigh(_ gameId: String) -> Entry? {
        entries.filter { $0.gameId == gameId && $0.kind == .highhand }
            .max { (($0.rank ?? -1), $0.ts) < (($1.rank ?? -1), $1.ts) }
    }

    public static let highHands = ["Three of a kind", "Straight", "Flush", "Full house", "Four of a kind", "Straight flush", "Royal flush"]
    public static func handText(_ e: Entry?) -> String {
        guard let e else { return "" }
        let cat = e.rank.flatMap { highHands.indices.contains($0) ? highHands[$0] : nil } ?? ""
        return [cat, e.note ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// All-time standings from settled games, jackpot and high hand payouts, and manual edits.
    public var board: [BoardRow] {
        struct Acc { var buyIn = 0.0, out = 0.0, games = Set<String>(), bbj = 0.0, hh = 0.0, best = -Double.infinity, inAdj = 0.0, netAdj = 0.0, gamesAdj = 0, adj = 0 }
        var t: [String: Acc] = [:]
        for g in games where g.status == .closed {
            for x in summary(g.id).seats {
                let pid = x.playerId, s = x.seat
                t[pid, default: Acc()].buyIn += s.buyIn
                t[pid, default: Acc()].out += s.cashOut
                t[pid, default: Acc()].games.insert(g.id)
                t[pid, default: Acc()].best = max(t[pid, default: Acc()].best, s.net)
            }
        }
        for e in entries {
            guard let pid = e.playerId else { continue }
            switch e.kind {
            case .jackpot: t[pid, default: Acc()].bbj += e.amount
            case .hhpay: t[pid, default: Acc()].hh += e.amount
            case .adjust:
                t[pid, default: Acc()].netAdj += e.amount
                t[pid, default: Acc()].inAdj += e.buyins ?? 0
                t[pid, default: Acc()].gamesAdj += e.games ?? 0
                t[pid, default: Acc()].adj += 1
            default: break
            }
        }
        return t.map { id, r in
            BoardRow(id: id, name: name(id), games: max(0, r.games.count + r.gamesAdj), buyIn: r.buyIn + r.inAdj,
                     net: r.out - r.buyIn + r.bbj + r.hh + r.netAdj, bbj: r.bbj, hh: r.hh,
                     best: r.best == -.infinity ? nil : r.best, edited: r.adj > 0)
        }
        .sorted { $0.net != $1.net ? $0.net > $1.net : $0.name < $1.name }
    }

    /// Total bought in across settled games plus standings edits.
    public var allTimeBuyIns: Double {
        games.filter { $0.status == .closed }.reduce(0) { $0 + summary($1.id).buy } + entries.filter { $0.kind == .adjust }.reduce(0) { $0 + ($1.buyins ?? 0) }
    }

    /// Fewest payments that square everyone up. Positive balances are owed money.
    public static func transfers(_ balances: [(name: String, amount: Double)]) -> [Transfer] {
        var cr = balances.filter { $0.amount > 0.004 }.sorted { $0.amount > $1.amount }
        var dr = balances.filter { $0.amount < -0.004 }.map { (name: $0.name, amount: -$0.amount) }.sorted { $0.amount > $1.amount }
        var out: [Transfer] = []
        var i = 0, j = 0
        while i < dr.count && j < cr.count {
            let x = (min(dr[i].amount, cr[j].amount) * 100).rounded() / 100
            if x > 0 { out.append(Transfer(from: dr[i].name, to: cr[j].name, amount: x)) }
            dr[i].amount -= x; cr[j].amount -= x
            if dr[i].amount < 0.005 { i += 1 }
            if cr[j].amount < 0.005 { j += 1 }
        }
        return out
    }

    /// "Collect after" settle-up: who pays who, with drops owed to the jackpot and high hand pot.
    public func settleTransfers(_ gameId: String) -> [Transfer] {
        let s = summary(gameId)
        var bal = s.seats.map { (name: name($0.playerId), amount: $0.seat.net) }
        if s.drop > 0 { bal.append((name: "Bad beat jackpot", amount: s.drop)) }
        if s.hh > 0 { bal.append((name: "High hand pot", amount: s.hh)) }
        return Ledger.transfers(bal)
    }

    /// Bad beat payout in whole cents. Rounding leftovers, or the table's share when nobody is picked, stay in the jackpot.
    public struct HitShares: Equatable, Sendable { public var loser: Double, winner: Double, each: Double, table: [String], left: Double }
    public static func hitShares(balance: Double, split: JackpotSplit, loser: String, winner: String, active: [String]) -> HitShares {
        let cents = Int((balance * 100).rounded())
        let table = active.filter { $0 != loser && $0 != winner }
        let l = Int((Double(cents) * split.loser / 100).rounded(.down))
        let w = Int((Double(cents) * split.winner / 100).rounded(.down))
        let each = table.isEmpty ? 0 : Int((Double(cents) * split.table / 100 / Double(table.count)).rounded(.down))
        return HitShares(loser: Double(l) / 100, winner: Double(w) / 100, each: Double(each) / 100, table: table,
                         left: Double(cents - l - w - each * table.count) / 100)
    }

    public static let chipDenominations = [25, 50, 100]
    public static func bigChipsTotal(_ g: Game) -> Double {
        Double(chipDenominations.reduce(0) { $0 + $1 * max(0, g.bigChips[String($1)] ?? 0) })
    }

    /// Seconds left on the high hand timer, or nil when it's off or not started.
    public static func highHandTimeLeft(_ g: Game, now: Date = Date()) -> TimeInterval? {
        guard g.hhTimer > 0, let start = g.hhTimerStart else { return nil }
        return start / 1000 + Double(g.hhTimer) * 60 - now.timeIntervalSince1970
    }
}
