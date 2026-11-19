import XCTest
@testable import PokerCore

final class LedgerTests: XCTestCase {
    private let players = [Player(id: "a", name: "Ana"), Player(id: "b", name: "Ben"), Player(id: "c", name: "Cal"), Player(id: "d", name: "Dee")]
    private var ts = 0.0
    private func e(_ kind: Entry.Kind, _ pid: String?, _ amount: Double, game: String? = "g1", hands: Int? = nil, rank: Int? = nil, note: String? = nil, fixed: Bool? = nil) -> Entry {
        ts += 1
        return Entry(id: "e\(Int(ts))", ts: ts, gameId: game, playerId: pid, kind: kind, amount: amount, hands: hands, note: note, rank: rank, fixed: fixed)
    }

    func testGameSummaryAndPot() {
        let entries = [e(.buyin, "a", 20), e(.buyin, "b", 20), e(.buyin, "a", 20), e(.buyin, "a", -20), e(.drop, nil, 5, hands: 5),
                       e(.hhdrop, nil, 3, hands: 3), e(.cashout, "b", 35)]
        let l = Ledger(players: players, games: [Game(id: "g1", name: "Thu")], entries: entries)
        let s = l.summary("g1")
        XCTAssertEqual(s.seats.map(\.playerId), ["a", "b"])
        XCTAssertEqual(s.seat("a"), Ledger.Seat(buyIn: 20, cashOut: 0, buys: 1, cashed: 0))
        XCTAssertEqual(s.seat("b")?.net, 15)
        XCTAssertEqual(s.buy, 40)
        XCTAssertEqual(s.onTable, 40 - 35 - 5 - 3)
        XCTAssertEqual(l.jackpot.balance, 5)
        XCTAssertEqual(l.jackpot.hands, 5)
        XCTAssertEqual(l.highHandPool.balance, 3)
    }

    func testDeletedGameDropsOut() {
        var g2 = Game(id: "g2", name: "Oops"); g2.status = .deleted
        let l = Ledger(players: players, games: [Game(id: "g1", name: "Thu"), g2],
                       entries: [e(.drop, nil, 10, game: "g2"), e(.drop, nil, 4)])
        XCTAssertEqual(l.games.map(\.id), ["g1"])
        XCTAssertEqual(l.jackpot.balance, 4)
    }

    func testBoardAndSettleAfter() {
        var g = Game(id: "g1", name: "Thu", collect: "after"); g.status = .closed; g.closedAt = 10
        let entries = [e(.buyin, "a", 50), e(.buyin, "b", 50), e(.buyin, "c", 50), e(.drop, nil, 6),
                       e(.cashout, "a", 120), e(.cashout, "b", 24), e(.cashout, "c", 0),
                       e(.jackpot, "c", 30, game: nil), e(.adjust, "d", 15, game: nil)]
        let l = Ledger(players: players, games: [g], entries: entries)
        XCTAssertEqual(l.board.map { "\($0.name) \(Money.format($0.net, signed: true))" }, ["Ana +$70", "Dee +$15", "Cal −$20", "Ben −$26"])
        XCTAssertEqual(l.board.first { $0.id == "c" }?.bbj, 30)
        XCTAssertTrue(l.board.first { $0.id == "d" }!.edited)
        // Ben −26, Cal −50 owe Ana +70 and the jackpot its 6.
        let t = l.settleTransfers("g1")
        XCTAssertEqual(t.reduce(0) { $0 + $1.amount }, 76)
        XCTAssertEqual(t.first, Ledger.Transfer(from: "Cal", to: "Ana", amount: 50))
        XCTAssertTrue(t.contains(Ledger.Transfer(from: "Ben", to: "Bad beat jackpot", amount: 6)))
    }

    func testHitSharesMatchWebApp() {
        // $100.01 at 40/30/30 with two others at the table: $40 / $30 / $15 / $15, 1 cent stays.
        let s = Ledger.hitShares(balance: 100.01, split: JackpotSplit(loser: 40, winner: 30, table: 30), loser: "a", winner: "b", active: ["a", "b", "c", "d"])
        XCTAssertEqual(s, Ledger.HitShares(loser: 40, winner: 30, each: 15, table: ["c", "d"], left: 0.01))
        let none = Ledger.hitShares(balance: 100, split: JackpotSplit(), loser: "a", winner: "b", active: ["a", "b"])
        XCTAssertEqual(none.left, 25)
    }

    func testHighHandRaceAndPayout() {
        let entries = [e(.hhdrop, nil, 20, hands: 10), e(.highhand, "b", 0, rank: 3, note: "Kings full"), e(.highhand, "c", 0, rank: 4, note: "Nines"),
                       e(.highhand, "a", 0, rank: 2)]
        var l = Ledger(players: players, games: [Game(id: "g1", name: "Thu")], entries: entries)
        XCTAssertEqual(l.highHand("g1")?.playerId, "c", "a later, weaker hand doesn't take over")
        l = Ledger(players: players, games: [Game(id: "g1", name: "Thu")], entries: Array(entries.prefix(3)))
        XCTAssertEqual(Ledger.handText(l.highHand("g1")), "Four of a kind · Nines")
        l.entries.append(e(.hhpay, "c", 20, note: "Four of a kind · Nines"))
        XCTAssertNil(l.highHand("g1"))
        XCTAssertEqual(l.highHandPool.balance, 0)
        XCTAssertEqual(l.nightHigh("g1")?.playerId, "c")
        l.entries.append(e(.hhpay, "b", 100, fixed: true))
        XCTAssertEqual(l.highHandPool.balance, 0, "house-paid prizes don't touch the drop pot")
        XCTAssertEqual(l.board.first { $0.id == "b" }?.hh, 100)
    }

    func testDecodesFirestoreStyleData() throws {
        let json = #"{"name":"Thursday","status":"open","createdAt":1700000000000,"buyIn":20,"drop":1,"collect":"after","hhTimer":30,"hhTimerStart":1700000100000,"bigChips":{"25":2,"100":1}}"#
        let g = try JSONDecoder().decode(Game.self, from: Data(json.utf8))
        XCTAssertTrue(g.collectAfter)
        XCTAssertEqual(Ledger.bigChipsTotal(g), 150)
        XCTAssertEqual(Ledger.highHandTimeLeft(g, now: Date(timeIntervalSince1970: 1_700_000_100)), 1800)
        let en = try JSONDecoder().decode(Entry.self, from: Data(#"{"ts":5,"gameId":"g","playerId":"a","kind":"weird","amount":3}"#.utf8))
        XCTAssertEqual(en.kind, .unknown)
        let st = try JSONDecoder().decode(ClubSettings.self, from: Data(#"{"bbj":true,"split":{"loser":90,"winner":5,"table":1},"show":{"pot":false}}"#.utf8))
        XCTAssertTrue(st.bbj)
        XCTAssertEqual(st.split, JackpotSplit(), "split that doesn't add to 100 falls back to the default")
        XCTAssertFalse(st.shows(.pot)); XCTAssertTrue(st.shows(.board))
    }
}
