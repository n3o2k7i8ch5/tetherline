import SwiftUI

struct ActionButton: View {
    let title: String
    var systemImage: String? = nil
    var tone: ActionTone = .standard
    var fillsWidth = false
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            if let systemImage { Label(title, systemImage: systemImage) }
            else { Text(title) }
        }
        .buttonStyle(ActionButtonStyle(tone: tone, fillsWidth: fillsWidth))
    }
}

enum ActionTone { case standard, secondary, attention }

// Explicit foreground/background pairs keep text readable in both appearances,
// including inactive windows; system accent tint no longer chooses white text.
struct ActionColors {
    let foreground: Color
    let background: Color
    let border: Color

    init(tone: ActionTone, dark: Bool, enabled: Bool = true) {
        let values: (UInt32, UInt32, UInt32)
        if !enabled {
            values = dark ? (0xA3A4AD, 0x292A2D, 0x3B3D43) : (0x666770, 0xF1F1F3, 0xDEDEE2)
        } else if tone == .secondary {
            values = dark ? (0xE0E1E6, 0x303136, 0x484A51) : (0x353740, 0xEEEFF2, 0xD3D5DC)
        } else if tone == .attention {
            values = dark ? (0xF0B7B0, 0x432D2D, 0x78504D) : (0x8F2927, 0xF5E6E5, 0xE3B8B5)
        } else {
            values = dark ? (0xD2DFF2, 0x2A3648, 0x465975) : (0x243F64, 0xE7EDF5, 0xBAC8DC)
        }
        foreground = Self.color(values.0)
        background = Self.color(values.1)
        border = Self.color(values.2)
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct ActionButtonStyle: ButtonStyle {
    var tone: ActionTone = .standard
    var fillsWidth = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let colors = ActionColors(tone: tone, dark: colorScheme == .dark, enabled: isEnabled)
        let shape = Capsule()
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .frame(minWidth: 76, maxWidth: fillsWidth ? .infinity : nil, minHeight: 34)
            .foregroundStyle(colors.foreground)
            .background {
                shape.fill(colors.background)
                shape.fill(Color.primary.opacity(isEnabled ? (configuration.isPressed ? 0.08 : hovering ? 0.035 : 0) : 0))
            }
            .overlay(shape.strokeBorder(contrast == .increased ? colors.foreground : colors.border,
                                        lineWidth: contrast == .increased ? 1.5 : 1))
            .clipShape(shape)
            .contentShape(shape)
            .onHover { hovering = $0 }
    }
}
