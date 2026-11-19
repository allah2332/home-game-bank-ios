/// Scores poker hands. A bigger number is a better hand; the bits from 20 up hold the category
/// (0 high card … 8 straight flush) and the lower bits hold the ranks that break ties.
public enum HandEvaluator {
    public static let categoryNames = ["High card", "Pair", "Two pair", "Three of a kind", "Straight",
                                       "Flush", "Full house", "Four of a kind", "Straight flush"]

    /// Highest straight in a rank bit mask, or -1. The wheel (A-2-3-4-5) counts as five-high (3).
    static func straight(_ m: Int) -> Int {
        var hi = 12
        while hi >= 4 {
            if (m >> (hi - 4)) & 31 == 31 { return hi }
            hi -= 1
        }
        return (m & 0x100F) == 0x100F ? 3 : -1
    }

    /// The n highest ranks in a mask, packed four bits each.
    static func top(_ m: Int, _ n: Int) -> Int {
        var v = 0, k = 0, r = 12
        while r >= 0 && k < n {
            if (m >> r) & 1 == 1 { v = (v << 4) | r; k += 1 }
            r -= 1
        }
        while k < n { v <<= 4; k += 1 }
        return v
    }

    /// Best hand from 5 to 7 cards.
    public static func evaluate(_ cards: [Int]) -> Int {
        withUnsafeTemporaryAllocation(of: Int.self, capacity: 21) { buf -> Int in
            buf.initialize(repeating: 0)
            // 0–12 rank counts, 13–16 suit rank masks, 17–20 suit counts
            var rm = 0
            for c in cards {
                let r = c % 13, s = c / 13
                buf[r] += 1
                buf[13 + s] |= 1 << r
                buf[17 + s] += 1
                rm |= 1 << r
            }
            for s in 0..<4 where buf[17 + s] >= 5 {
                let h = straight(buf[13 + s])
                return h >= 0 ? (8 << 20) | h : (5 << 20) | top(buf[13 + s], 5)
            }
            var q = -1, t1 = -1, t2 = -1, p1 = -1, p2 = -1
            var r = 12
            while r >= 0 {
                switch buf[r] {
                case 4: q = r
                case 3: if t1 < 0 { t1 = r } else if t2 < 0 { t2 = r }
                case 2: if p1 < 0 { p1 = r } else if p2 < 0 { p2 = r }
                default: break
                }
                r -= 1
            }
            if q >= 0 { return (7 << 20) | (q << 16) | (top(rm & ~(1 << q), 1) << 12) }
            if t1 >= 0 && (t2 >= 0 || p1 >= 0) { return (6 << 20) | (t1 << 16) | (max(t2, p1) << 12) }
            let st = straight(rm)
            if st >= 0 { return (4 << 20) | st }
            if t1 >= 0 { return (3 << 20) | (t1 << 16) | (top(rm & ~(1 << t1), 2) << 8) }
            if p2 >= 0 { return (2 << 20) | (p1 << 16) | (p2 << 12) | (top(rm & ~(1 << p1) & ~(1 << p2), 1) << 8) }
            if p1 >= 0 { return (1 << 20) | (p1 << 16) | (top(rm & ~(1 << p1), 3) << 4) }
            return top(rm, 5)
        }
    }

    /// Omaha: exactly two hole cards and three board cards.
    public static func omaha(hole: [Int], board: [Int]) -> Int {
        var best = -1
        var five = [0, 0, 0, 0, 0]
        let h = hole.count, b = board.count
        guard h >= 2, b >= 3 else { return -1 }
        for i in 0..<(h - 1) {
            for j in (i + 1)..<h {
                five[0] = hole[i]; five[1] = hole[j]
                for a in 0..<(b - 2) {
                    for c in (a + 1)..<(b - 1) {
                        for d in (c + 1)..<b {
                            five[2] = board[a]; five[3] = board[c]; five[4] = board[d]
                            let v = evaluate(five)
                            if v > best { best = v }
                        }
                    }
                }
            }
        }
        return best
    }

    public static func name(_ v: Int) -> String {
        let cat = v >> 20
        if cat == 8 && (v & 15) == 12 { return "Royal flush" }
        return categoryNames.indices.contains(cat) ? categoryNames[cat] : ""
    }
}
