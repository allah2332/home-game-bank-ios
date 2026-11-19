import XCTest
@testable import PokerCore

private func c(_ s: String) -> Int { Card(text: s)!.id }
private func cs(_ a: [String]) -> [Int] { a.map(c) }

final class EvaluatorTests: XCTestCase {
    func testNames() {
        XCTAssertEqual(HandEvaluator.name(HandEvaluator.evaluate(cs(["As", "Ks", "Qs", "Js", "Ts", "2d", "3c"]))), "Royal flush")
        XCTAssertEqual(HandEvaluator.name(HandEvaluator.evaluate(cs(["5s", "4d", "3c", "2h", "Ad", "Kd", "9c"]))), "Straight")
        XCTAssertEqual(HandEvaluator.name(HandEvaluator.evaluate(cs(["9s", "9d", "9c", "4h", "4d", "Kc", "2s"]))), "Full house")
        XCTAssertEqual(HandEvaluator.name(HandEvaluator.evaluate(cs(["9s", "9d", "4c", "4h", "2d", "2c", "Ks"]))), "Two pair")
    }

    func testTieBreaks() {
        XCTAssertLessThan(HandEvaluator.evaluate(cs(["5s", "4d", "3c", "2h", "Ad"])), HandEvaluator.evaluate(cs(["6s", "5d", "4c", "3h", "2d"])), "wheel is the lowest straight")
        XCTAssertGreaterThan(HandEvaluator.evaluate(cs(["Ah", "Ad", "Kc", "7s", "5d", "3c", "2h"])), HandEvaluator.evaluate(cs(["Ah", "Ad", "Qc", "7s", "5d", "3c", "2h"])), "kicker")
        XCTAssertGreaterThan(HandEvaluator.evaluate(cs(["Kh", "Kd", "Qc", "Qs", "Jd", "Jc", "2h"])), HandEvaluator.evaluate(cs(["Kh", "Kd", "Qc", "Qs", "Td", "Tc", "9h"])), "third pair plays as kicker")
    }

    func testOmahaRules() {
        // One heart in hand with four on the board is not a flush in Omaha.
        XCTAssertEqual(HandEvaluator.name(HandEvaluator.omaha(hole: cs(["Ah", "2c", "3d", "4s"]), board: cs(["Kh", "Qh", "Jh", "5h", "8c"]))), "High card")
        XCTAssertEqual(HandEvaluator.name(HandEvaluator.omaha(hole: cs(["Ah", "Kh", "2c", "3d"]), board: cs(["Qh", "Jh", "9h", "4c", "7s"]))), "Flush")
        XCTAssertEqual(HandEvaluator.name(HandEvaluator.omaha(hole: cs(["As", "Kd", "2c", "3h"]), board: cs(["Ah", "Ad", "Ac", "7s", "9d"]))), "Four of a kind")
    }

    /// Compares against a slow, obviously-correct scorer on random hands.
    func testMatchesBruteForce() {
        func score5(_ h: [Int]) -> [Int] {
            let rs = h.map { $0 % 13 }.sorted(by: >), flush = Set(h.map { $0 / 13 }).count == 1
            var st = -1
            if Set(rs).count == 5 { if rs[0] - rs[4] == 4 { st = rs[0] } else if rs == [12, 3, 2, 1, 0] { st = 3 } }
            var cnt: [Int: Int] = [:]; rs.forEach { cnt[$0, default: 0] += 1 }
            let g = cnt.map { ($0.value, $0.key) }.sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 > $1.1 }
            let ranks = g.map { $0.1 }
            if st >= 0 && flush { return [8, st] }
            if g[0].0 == 4 { return [7] + ranks }
            if g[0].0 == 3 && g[1].0 == 2 { return [6] + ranks }
            if flush { return [5] + rs }
            if st >= 0 { return [4, st] }
            if g[0].0 == 3 { return [3] + ranks }
            if g[0].0 == 2 && g[1].0 == 2 { return [2] + ranks }
            if g[0].0 == 2 { return [1] + ranks }
            return [0] + rs
        }
        func best7(_ h: [Int]) -> [Int] {
            var best: [Int] = []
            for a in 0..<7 { for b in (a + 1)..<7 {
                let s = score5(h.enumerated().filter { $0.offset != a && $0.offset != b }.map(\.element))
                if best.isEmpty || s.lexicographicallyPrecedes(best) == false && s != best { best = s }
            } }
            return best
        }
        var rng = XorShift64(seed: 42)
        for _ in 0..<4000 {
            var d = Array(0..<52); d.shuffle(using: &rng)
            let a = Array(d[0..<7]), b = Array(d[7..<14])
            let fast = (HandEvaluator.evaluate(a) - HandEvaluator.evaluate(b)).signum()
            let ra = best7(a), rb = best7(b)
            let slow = ra == rb ? 0 : (rb.lexicographicallyPrecedes(ra) ? 1 : -1)
            XCTAssertEqual(fast, slow, "\(a) vs \(b)")
        }
    }
}

final class EquityTests: XCTestCase {
    func testAcesVersusKings() {
        let r = Equity.run(seats: [[c("As"), c("Ah")], [c("Ks"), c("Kh")]], board: [nil, nil, nil, nil, nil], hole: 2,
                           maxIterations: 200_000, timeBudget: 30, seed: 7)!
        XCTAssertEqual(r.equity[0], 82.6, accuracy: 1.0)
        XCTAssertEqual(r.equity[0] + r.equity[1], 100, accuracy: 0.001)
    }

    func testExactChop() {
        let r = Equity.run(seats: [[c("As"), c("Kd")], [c("Ac"), c("Kh")]], board: [c("2s"), c("7d"), c("9c"), c("Th"), c("3s")], hole: 2)!
        XCTAssertTrue(r.exact)
        XCTAssertEqual(r.equity, [50, 50])
        XCTAssertEqual(r.tie, [100, 100])
    }

    func testExactOnTheFlop() {
        // Same spot the web app reports as exact 25.6 / 74.4.
        let r = Equity.run(seats: [[c("Ah"), c("Kh")], [c("Qs"), c("Qd")]], board: [c("2h"), c("7h"), c("Qc"), nil, nil], hole: 2)!
        XCTAssertTrue(r.exact)
        XCTAssertEqual(r.equity[0], 25.6, accuracy: 0.1)
    }

    func testRiverSettlesIt() {
        let r = Equity.run(seats: [[c("As"), c("Ah")], [c("Ks"), c("Kh")]], board: [c("2d"), c("7c"), c("Kd"), c("Ad"), c("3c")], hole: 2)!
        XCTAssertEqual(r.equity, [100, 0])
    }

    func testOmahaRunsAndSumsTo100() {
        let r = Equity.run(seats: [[c("As"), c("Ah"), c("Ks"), c("Kh")], [c("Jc"), c("Td"), c("9c"), c("8d")]], board: [nil, nil, nil, nil, nil], hole: 4,
                           maxIterations: 20_000, timeBudget: 30, seed: 3)!
        XCTAssertEqual(r.equity[0] + r.equity[1], 100, accuracy: 0.001)
        XCTAssertEqual(r.equity[0], 61.6, accuracy: 2.5)
    }

    func testCancel() {
        let r = Equity.run(seats: [[c("As"), c("Ah")], [nil, nil]], board: [nil, nil, nil, nil, nil], hole: 2, isCancelled: { true })
        XCTAssertNil(r)
    }
}

final class SessionTests: XCTestCase {
    private func s(_ date: String, _ mins: Int, _ game: String, _ loc: String, _ buy: Double, _ out: Double, tips: Double = 0, tourney: Bool = false) -> Session {
        Session(type: tourney ? "tourney" : "cash", date: date, mins: mins, game: game, loc: loc, buy: buy, out: out, tips: tips)
    }
    private lazy var sample: [Session] = [
        s("2026-07-10", 240, "NL Texas Holdem", "SIENA", 300, 800),
        s("2026-08-03", 330, "NL Texas Holdem", "Gian", 500, 200, tips: 20),
        s("2026-09-15", 180, "NL Omaha", "SIENA", 700, 0),
        s("2026-10-21", 360, "NL Texas Holdem", "Office", 200, 900, tips: 15),
        s("2026-11-12", 120, "Deepstack", "WPT", 150, 0, tourney: true),
        s("2026-11-16", 300, "Deepstack", "WPT", 150, 600, tourney: true),
    ]

    func testSummaryMatchesWebApp() {
        let m = SessionStats.summary(sample)
        XCTAssertEqual(m.profit, 500)
        XCTAssertEqual(m.minutes, 1530)
        XCTAssertEqual(Money.format(m.perHour!, signed: true), "+$19.61")
        XCTAssertEqual(Money.format(m.perSession!, signed: true), "+$83.33")
        XCTAssertEqual(SessionStats.duration(m.minutes), "25 h 30 m")
        XCTAssertEqual(m.wins, 3); XCTAssertEqual(m.tourneys, 2); XCTAssertEqual(m.cashed, 1); XCTAssertEqual(m.tips, 35)
    }

    func testGroups() {
        XCTAssertEqual(SessionStats.groups(sample, by: .location).map { "\($0.label) \(Money.format($0.profit, signed: true)) \($0.hours)" },
                       ["Office +$700 6", "WPT +$300 7", "SIENA −$200 7", "Gian −$300 6"])
        XCTAssertEqual(SessionStats.groups(sample, by: .month).map(\.label), ["July", "August", "September", "October", "November"])
        XCTAssertEqual(SessionStats.groups(sample, by: .weekday).map { "\($0.label) \($0.hours)" },
                       ["Monday 11", "Tuesday 3", "Wednesday 6", "Thursday 2", "Friday 4"])
    }

    func testCumulative() {
        XCTAssertEqual(SessionStats.cumulative(sample).map(\.total), [500, 200, -500, 200, 50, 500])
    }

    func testSpanPastMidnight() {
        XCTAssertEqual(SessionStats.spanMinutes(start: "22:30", end: "03:15"), 285)
        XCTAssertEqual(SessionStats.spanMinutes(start: "13:17", end: "17:17"), 240)
        XCTAssertEqual(SessionStats.spanMinutes(start: "", end: "17:17"), 0)
    }

    func testReadsWebBackup() throws {
        let json = #"{"app":"home-game-bank","kind":"sessions","v":1,"start":1000,"sessions":[{"id":"s1","ts":1,"type":"tourney","date":"2026-11-16","mins":300,"game":"Deepstack","loc":"WPT","buy":150,"out":600,"tips":0},{"id":"bad","date":"nope","buy":1,"out":2},{"id":"s2","date":"2026-11-17","start":"20:00","end":"23:30","mins":210,"buy":100,"out":40}]}"#
        let b = try SessionBackup.decode(Data(json.utf8))
        XCTAssertEqual(b.start, 1000)
        XCTAssertEqual(b.sessions.map(\.id), ["s1", "s2"])
        XCTAssertEqual(b.sessions[1].profit, -60)
        XCTAssertEqual(b.sessions[1].type, "cash")
        let again = try SessionBackup.decode(JSONEncoder().encode(b))
        XCTAssertEqual(again.sessions, b.sessions)
    }

    func testMoney() {
        XCTAssertEqual(Money.format(1234), "$1,234")
        XCTAssertEqual(Money.format(12.5), "$12.50")
        XCTAssertEqual(Money.format(-27, signed: true), "−$27")
        XCTAssertEqual(Money.format(0, signed: true), "$0")
        XCTAssertEqual(Money.short(-1500), "−$1.5k")
        XCTAssertEqual(Money.short(500), "$500")
    }
}
