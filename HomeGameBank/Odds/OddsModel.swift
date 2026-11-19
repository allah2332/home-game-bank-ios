import Foundation
import Observation
import PokerCore

/// State for the odds calculator: who holds what, the board, which card spot is selected, and the result.
@Observable
final class OddsModel {
    enum Game: String, CaseIterable {
        case holdem = "Hold'em", plo = "PLO"
        var hole: Int { self == .holdem ? 2 : 4 }
    }
    enum Slot: Hashable {
        case seat(Int, Int)
        case board(Int)
    }

    var game: Game = .holdem
    var players = 6
    var seats: [[Int?]] = OddsModel.emptySeats()
    var board: [Int?] = [nil, nil, nil, nil, nil]
    var selection: Slot? = .seat(0, 0)
    var result: EquityResult?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init() {
        if LaunchOptions.demo {
            for (slot, text) in [(Slot.seat(0, 0), "As"), (.seat(0, 1), "Ah"), (.seat(1, 0), "Ks"), (.seat(1, 1), "Kh"),
                                 (.board(0), "2d"), (.board(1), "7c"), (.board(2), "Jh")] {
                set(slot, Card(text: text)?.id)
            }
            selection = .seat(2, 0)
            recalc()
        }
    }

    static func emptySeats() -> [[Int?]] { Array(repeating: [nil, nil, nil, nil], count: 10) }

    var hole: Int { game.hole }

    var order: [Slot] {
        (0..<players).flatMap { p in (0..<hole).map { Slot.seat(p, $0) } } + (0..<5).map { Slot.board($0) }
    }

    func card(_ s: Slot) -> Int? {
        switch s {
        case .seat(let p, let j): return seats[p][j]
        case .board(let i): return board[i]
        }
    }

    private func set(_ s: Slot, _ c: Int?) {
        switch s {
        case .seat(let p, let j): seats[p][j] = c
        case .board(let i): board[i] = c
        }
    }

    var used: Set<Int> {
        Set(seats.prefix(players).flatMap { $0.prefix(hole).compactMap { $0 } } + board.compactMap { $0 })
    }

    private func nextEmpty(after s: Slot) -> Slot? {
        let o = order
        let i = o.firstIndex(of: s) ?? (o.count - 1)
        return (Array(o[(i + 1)...]) + Array(o[...i])).first { card($0) == nil }
    }

    /// A card was tapped in the deck: it goes into the selected spot, then the selection moves on.
    func pick(_ c: Int) {
        if selection == nil { selection = nextEmpty(after: .board(4)) }
        guard let s = selection, !used.contains(c) else { return }
        set(s, c)
        selection = nextEmpty(after: s)
        recalc()
    }

    /// A spot on the table was tapped: select it, or take its card back if it was already selected.
    func tap(_ s: Slot) {
        if selection == s, card(s) != nil { set(s, nil); recalc() } else { selection = s }
    }

    func changePlayers(by d: Int) {
        players = min(10, max(2, players + d))
        for i in players..<10 { seats[i] = [nil, nil, nil, nil] }
        if case .seat(let p, _)? = selection, p >= players { selection = nextEmpty(after: .board(4)) }
        recalc()
    }

    func setGame(_ g: Game) {
        guard g != game else { return }
        game = g
        reset()
    }

    func reset() {
        seats = OddsModel.emptySeats()
        board = [nil, nil, nil, nil, nil]
        selection = .seat(0, 0)
        recalc()
    }

    /// Result for the current table, ignoring a stale one from before a player was added or removed.
    var current: EquityResult? { result?.equity.count == players ? result : nil }

    func handName(seat i: Int) -> String? {
        let h = seats[i].prefix(hole).compactMap { $0 }, b = board.compactMap { $0 }
        guard h.count == hole, b.count >= 3 else { return nil }
        return HandEvaluator.name(hole == 4 ? HandEvaluator.omaha(hole: h, board: b) : HandEvaluator.evaluate(h + b))
    }

    func recalc() {
        task?.cancel()
        generation += 1
        let gen = generation
        let s = seats.prefix(players).map { Array($0.prefix(hole)) }
        guard s.contains(where: { $0.contains { $0 != nil } }) else { result = nil; return }
        let b = board, h = hole
        task = Task.detached(priority: .userInitiated) { [weak self] in
            _ = Equity.run(seats: s, board: b, hole: h,
                       maxIterations: h == 4 ? 40_000 : 120_000, timeBudget: h == 4 ? 1.6 : 0.9,
                       isCancelled: { Task.isCancelled }) { r in
                DispatchQueue.main.async {
                    guard let self, self.generation == gen else { return }
                    self.result = r
                }
            }
        }
    }
}
