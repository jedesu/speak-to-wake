import SwiftUI

/// "Soft Dawn" (Coral): warm off-white ground, white rounded cards, one coral accent.
/// Chosen from the design canvas (see CLAUDE.md). Text colors pass 4.5:1 contrast.
enum Theme {
    static let ground = Color(hex: 0xF6F1EB)
    static let card = Color.white
    static let text = Color(hex: 0x2B2420)
    static let muted = Color(hex: 0x6E625A)
    /// Text on cards for something that's switched off.
    static let off = Color(hex: 0x8A7E76)
    static let accent = Color(hex: 0xC24E2E)
    /// Accent for small text (links), a bit darker for contrast.
    static let link = Color(hex: 0xA8432B)
    /// Light fill for chips, hint circles and secondary buttons.
    static let chip = Color(hex: 0xF1E7DF)
    static let toggleOff = Color(hex: 0xE8DED6)
    /// Tinted card for tips.
    static let tip = Color(hex: 0xEFE5DC)

    static let cardRadius: CGFloat = 28
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    /// A white rounded card with a soft shadow.
    func card(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: Theme.cardRadius))
            .shadow(color: Color(hex: 0x4C3424).opacity(0.06), radius: 10, y: 2)
    }

    /// Lists and forms on the warm ground instead of system gray.
    func softDawnList() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Theme.ground)
    }
}

/// The big pill button used for main actions.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.bold())
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(.white)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1), in: .capsule)
    }
}

/// Light chip-colored pill for secondary actions (Show hint, etc.).
struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .foregroundStyle(Theme.text)
            .background(Theme.chip.opacity(configuration.isPressed ? 0.7 : 1), in: .capsule)
    }
}
