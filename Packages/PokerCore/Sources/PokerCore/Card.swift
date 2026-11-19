/// A playing card stored as 0–51: rank = id % 13 (0 is a 2, 12 is an ace), suit = id / 13
/// (0 spades, 1 hearts, 2 diamonds, 3 clubs). Same numbering as the web app.
public struct Card: Hashable, Identifiable, Codable, Sendable {
    public let id: Int

    public init(_ id: Int) {
        precondition((0..<52).contains(id), "card id out of range")
        self.id = id
    }

    /// Parses text like "As", "Td", "10h", "Kc".
    public init?(text: String) {
        let t = text.uppercased()
        guard let s = t.last, let suit = Card.suitLetters.firstIndex(of: s) else { return nil }
        var r = String(t.dropLast())
        if r == "10" { r = "T" }
        guard let rank = Card.rankLetters.firstIndex(of: r) else { return nil }
        self.id = suit * 13 + rank
    }

    public var rank: Int { id % 13 }
    public var suit: Int { id / 13 }
    public var rankLabel: String { Card.rankLabels[rank] }
    public var suitSymbol: String { Card.suitSymbols[suit] }
    public var label: String { rankLabel + suitSymbol }

    public static let rankLabels = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
    public static let suitSymbols = ["♠", "♥", "♦", "♣"]
    static let rankLetters = ["2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A"]
    static let suitLetters: [Character] = ["S", "H", "D", "C"]

    /// The deck in picker order: each suit from ace down to two.
    public static let pickerOrder: [Int] = (0..<4).flatMap { s in (0..<13).reversed().map { s * 13 + $0 } }
}
