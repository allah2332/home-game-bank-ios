import SwiftUI
import PokerCore

struct OddsView: View {
    @State private var m = OddsModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Hand odds").font(.app(22, .bold)).foregroundStyle(Theme.text)
                    Spacer()
                    Button("New hand") { m.reset() }.buttonStyle(PillButtonStyle())
                }
                HStack(spacing: 8) {
                    PillPicker(options: OddsModel.Game.allCases.map { ($0, $0.rawValue) },
                               selection: Binding(get: { m.game }, set: { m.setGame($0) }))
                        .frame(width: 168)
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        RoundIconButton(symbol: "minus", label: "One less player") { m.changePlayers(by: -1) }.disabled(m.players <= 2)
                        Text("\(m.players)").font(.app(17, .bold)).monospacedDigit().frame(minWidth: 22)
                        RoundIconButton(symbol: "plus", label: "One more player") { m.changePlayers(by: 1) }.disabled(m.players >= 10)
                    }
                }
                DeckGrid(m: m)
                TableView(m: m)
                    .aspectRatio(m.hole == 4 ? 3.0 / 4.0 : 4.0 / 5.0, contentMode: .fit)
                    .padding(.vertical, m.hole == 4 ? 24 : 12)
            }
            .cardSurface()
            .padding(12)
        }
        .scrollIndicators(.hidden)
    }
}

struct RoundIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold))
                .frame(width: 36, height: 36)
                .foregroundStyle(enabled ? Theme.text : Theme.text2.opacity(0.5))
                .background(Theme.fill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The 52 cards in four colour rows. Cards already on the table fade out.
struct DeckGrid: View {
    let m: OddsModel
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 3), count: 13)

    var body: some View {
        let used = m.used
        LazyVGrid(columns: cols, spacing: 3) {
            ForEach(Card.pickerOrder, id: \.self) { id in
                let card = Card(id)
                Button { m.pick(id) } label: {
                    CardFace(card: card, size: 13).frame(height: 42)
                }
                .buttonStyle(.plain)
                .disabled(used.contains(id))
                .opacity(used.contains(id) ? 0.15 : 1)
                .accessibilityLabel(card.label)
            }
        }
    }
}

struct CardFace: View {
    let card: Card
    var size: CGFloat = 15
    var body: some View {
        VStack(spacing: 1) {
            Text(card.rankLabel).font(.app(size, .bold))
            Text(card.suitSymbol).font(.system(size: size * 0.8))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.suits[card.suit], in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// One card spot on the table: a face when picked, a card back when empty, green ring when selected.
struct SlotView: View {
    let m: OddsModel
    let slot: OddsModel.Slot
    let w: CGFloat
    let h: CGFloat

    var body: some View {
        let c = m.card(slot), selected = m.selection == slot
        Button { m.tap(slot) } label: {
            ZStack {
                if let c {
                    CardFace(card: Card(c), size: w * 0.42)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.cardBack)
                }
            }
            .frame(width: w, height: h)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(selected ? Theme.accent : (c != nil ? Color.white.opacity(0.85) : Theme.cardEdge), lineWidth: selected ? 3 : 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c.map { Card($0).label } ?? "Empty card")
    }
}

struct TableView: View {
    let m: OddsModel

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let plo = m.hole == 4
            let cw: CGFloat = plo ? 27 : 34, ch: CGFloat = plo ? 37 : 48
            let r = m.current
            let lead = r.map { $0.done ? ($0.equity.max() ?? -1) : -1 } ?? -1
            ZStack {
                Ellipse()
                    .fill(RadialGradient(colors: [Color(hex: 0x23925A), Color(hex: 0x167443), Color(hex: 0x0E5431)], center: .center, startRadius: 0, endRadius: W * 0.45))
                    .overlay(Ellipse().strokeBorder(Color(hex: 0x15161A), lineWidth: 9))
                    .overlay(Ellipse().inset(by: 9).strokeBorder(Color(hex: 0x2C2E35), lineWidth: 2))
                    .frame(width: W * 0.72, height: H * 0.76)
                    .position(x: W / 2, y: H / 2)

                VStack(spacing: 4) {
                    HStack(spacing: 10) {
                        HStack(spacing: 3) { ForEach(0..<3, id: \.self) { SlotView(m: m, slot: .board($0), w: 34, h: 48) } }
                        HStack(spacing: 3) { ForEach(3..<5, id: \.self) { SlotView(m: m, slot: .board($0), w: 34, h: 48) } }
                    }
                    Text(r.map { $0.exact ? "Exact" : ($0.done ? " " : "Working…") } ?? " ")
                        .font(.app(11)).foregroundStyle(.white.opacity(0.7))
                }
                .position(x: W / 2, y: H / 2)

                ForEach(0..<m.players, id: \.self) { i in
                    let a = 2 * Double.pi * Double(i) / Double(m.players)
                    VStack(spacing: 3) {
                        if plo {
                            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                                GridRow { SlotView(m: m, slot: .seat(i, 0), w: cw, h: ch); SlotView(m: m, slot: .seat(i, 1), w: cw, h: ch) }
                                GridRow { SlotView(m: m, slot: .seat(i, 2), w: cw, h: ch); SlotView(m: m, slot: .seat(i, 3), w: cw, h: ch) }
                            }
                        } else {
                            HStack(spacing: 3) { SlotView(m: m, slot: .seat(i, 0), w: cw, h: ch); SlotView(m: m, slot: .seat(i, 1), w: cw, h: ch) }
                        }
                        SeatLabel(index: i, result: r, lead: lead, hand: m.handName(seat: i))
                    }
                    .position(x: W * (0.5 + 0.41 * sin(a)), y: H * (0.5 + 0.42 * cos(a)))
                }
            }
        }
    }
}

struct SeatLabel: View {
    let index: Int
    let result: EquityResult?
    let lead: Double
    let hand: String?

    var body: some View {
        VStack(spacing: 0) {
            Text("P\(index + 1)").font(.app(11)).foregroundStyle(Theme.text2)
            if let r = result {
                Text(String(format: "%.1f%%", r.equity[index])).font(.app(14, .bold)).monospacedDigit()
                    .foregroundStyle(r.equity[index] == lead ? Theme.accent : Theme.text)
                Text(String(format: "W %.1f · T %.1f", r.win[index], r.tie[index])).font(.app(10)).monospacedDigit().foregroundStyle(Theme.text2)
            } else {
                Text("—").font(.app(14, .bold)).foregroundStyle(Theme.text)
            }
            if let hand { Text(hand).font(.app(10)).foregroundStyle(Theme.text2) }
        }
        .fixedSize()
    }
}
