import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// Same colours as the web app's tokens.css: one dark theme, raised cards, one green accent.
enum Theme {
    static let bg = Color(hex: 0x0C0D10)
    static let surface = Color(hex: 0x191A1F)
    static let fill = Color(hex: 0x26282E)
    static let fill2 = Color(hex: 0x32353C)
    static let text = Color(hex: 0xF5F5F6)
    static let text2 = Color(hex: 0x9B9DA6)
    static let border = Color(hex: 0x2A2C33)
    static let borderStrong = Color(hex: 0x3A3D45)
    static let accent = Color(hex: 0x57D98A)
    static let onAccent = Color(hex: 0x06210F)
    static let pos = Color(hex: 0x57D98A)
    static let neg = Color(hex: 0xF2777A)
    /// Four-colour deck: spades, hearts, diamonds, clubs.
    static let suits = [Color(hex: 0x3D4048), Color(hex: 0xD2434B), Color(hex: 0x2F6FD1), Color(hex: 0x2A9A55)]
    static let cardBack = Color(hex: 0x1D1F24)
    static let cardEdge = Color(hex: 0x4A4D56)
    static let winBox = Color(hex: 0x2A9A55)
    static let lossBox = Color(hex: 0xC8383D)

    static func result(_ v: Double) -> Color { v > 0.004 ? pos : v < -0.004 ? neg : text }
}

extension Font {
    /// Rounded system type stands in for the web app's Outfit.
    static func app(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .rounded) }
}

struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    func cardSurface() -> some View { modifier(CardSurface()) }
}

struct PillButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.app(15, .semibold)).lineLimit(1).fixedSize()
            .padding(.horizontal, 14).frame(minHeight: 40)
            .foregroundStyle(primary ? Theme.onAccent : Theme.text)
            .background(primary ? Theme.accent : Theme.fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Segmented control in the app's pill style (the system one can't take these colours).
struct PillPicker<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let value = options[i].0, label = options[i].1
                Button { selection = value } label: {
                    Text(label).font(.app(14, selection == value ? .semibold : .medium)).lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 32)
                        .foregroundStyle(selection == value ? Theme.onAccent : Theme.text2)
                        .background(selection == value ? Theme.accent : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(3).background(Theme.fill, in: Capsule())
    }
}
