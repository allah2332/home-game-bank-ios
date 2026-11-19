import Foundation

/// Each seat's share of the pot in percent. Ties split the pot, so equity = win + tie share.
public struct EquityResult: Equatable, Sendable {
    public var iterations: Int
    public var exact: Bool
    public var done: Bool
    public var equity: [Double]
    public var win: [Double]
    public var tie: [Double]
}

/// Small fast random generator for the simulation (not for anything security related).
public struct XorShift64: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    public mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

public enum Equity {
    /// Works out equity for every seat. Unpicked cards are dealt at random.
    /// Exact when every hand is known and only the turn and/or river are left; otherwise a random sample
    /// that reports progress after each chunk and stops at `maxIterations` or `timeBudget` seconds.
    /// - Parameters:
    ///   - seats: each seat's hole cards (nil = unknown); every seat has `hole` entries.
    ///   - board: five board slots (nil = not dealt yet).
    ///   - hole: 2 for Hold'em, 4 for Omaha (exactly two hole cards and three board cards).
    @discardableResult
    public static func run(seats: [[Int?]], board: [Int?], hole: Int,
                           maxIterations: Int = 120_000, timeBudget: TimeInterval = 0.9,
                           chunk: Int = 2_000, seed: UInt64? = nil,
                           isCancelled: () -> Bool = { false },
                           progress: (EquityResult) -> Void = { _ in }) -> EquityResult? {
        let n = seats.count
        guard n >= 2 else { return nil }
        var used = Set<Int>()
        for s in seats { for c in s { if let c { used.insert(c) } } }
        for c in board { if let c { used.insert(c) } }
        let deck = (0..<52).filter { !used.contains($0) }
        let holes = seats.map { $0.compactMap { $0 } }
        let needS = holes.map { hole - $0.count }
        let bk = board.compactMap { $0 }
        let needB = 5 - bk.count
        let need = needS.reduce(0, +) + needB
        guard need <= deck.count, needS.allSatisfy({ $0 >= 0 }), needB >= 0 else { return nil }

        var eq = [Double](repeating: 0, count: n), win = eq, tie = eq
        var sc = [Int](repeating: 0, count: n)
        var iters = 0
        var hc = [Int](); hc.reserveCapacity(hole)
        var bd = [Int](repeating: 0, count: 5)
        var seven = [Int](repeating: 0, count: 7)

        // `draw` holds the board cards first, then each seat's missing cards in seat order.
        func deal(_ draw: [Int]) {
            for j in 0..<bk.count { bd[j] = bk[j] }
            for j in 0..<needB { bd[bk.count + j] = draw[j] }
            var k = needB, best = -1, nb = 0
            for p in 0..<n {
                hc.removeAll(keepingCapacity: true)
                hc.append(contentsOf: holes[p])
                for _ in 0..<needS[p] { hc.append(draw[k]); k += 1 }
                let v: Int
                if hole == 4 {
                    v = HandEvaluator.omaha(hole: hc, board: bd)
                } else {
                    seven[0] = hc[0]; seven[1] = hc[1]
                    for j in 0..<5 { seven[2 + j] = bd[j] }
                    v = HandEvaluator.evaluate(seven)
                }
                sc[p] = v
                if v > best { best = v; nb = 1 } else if v == best { nb += 1 }
            }
            for p in 0..<n where sc[p] == best {
                eq[p] += 1 / Double(nb)
                if nb == 1 { win[p] += 1 } else { tie[p] += 1 }
            }
            iters += 1
        }
        func report(done: Bool, exact: Bool) -> EquityResult {
            let d = Double(max(iters, 1))
            return EquityResult(iterations: iters, exact: exact, done: done,
                                equity: eq.map { $0 / d * 100 }, win: win.map { $0 / d * 100 }, tie: tie.map { $0 / d * 100 })
        }

        if needS.allSatisfy({ $0 == 0 }) && needB <= 2 {
            switch needB {
            case 0: deal([])
            case 1: for a in deck { deal([a]) }
            default:
                for i in 0..<deck.count { for j in (i + 1)..<deck.count { deal([deck[i], deck[j]]) } }
            }
            let r = report(done: true, exact: true)
            progress(r)
            return r
        }

        var rng = XorShift64(seed: seed ?? UInt64(truncatingIfNeeded: Int64(Date().timeIntervalSince1970 * 1_000_000)) | 1)
        var work = deck
        var draw = [Int](repeating: 0, count: need)
        let start = Date()
        while true {
            var c = 0
            while c < chunk && iters < maxIterations {
                for j in 0..<need {
                    let r = j + Int(rng.next() % UInt64(work.count - j))
                    work.swapAt(j, r)
                    draw[j] = work[j]
                }
                deal(draw)
                c += 1
            }
            if isCancelled() { return nil }
            let done = iters >= maxIterations || Date().timeIntervalSince(start) > timeBudget
            let r = report(done: done, exact: false)
            progress(r)
            if done { return r }
        }
    }
}
