import SwiftUI

enum CodexPalette {
    static let canvas = Color.dynamic(light: 0xEBF0F7, dark: 0x101722)
    static let surface = Color.dynamic(light: 0xF8FAFD, dark: 0x182231)
    static let raised = Color.dynamic(light: 0xFFFFFF, dark: 0x202C3D)
    static let ink = Color.dynamic(light: 0x182235, dark: 0xEEF3FB)
    static let secondaryInk = Color.dynamic(light: 0x627086, dark: 0xAAB7CA)
    static let line = Color.dynamic(light: 0xD3DCE9, dark: 0x334156)
    static let cobalt = Color.dynamic(light: 0x315FDB, dark: 0x7FA4FF)
    static let teal = Color.dynamic(light: 0x287D78, dark: 0x62C8BE)
    static let amber = Color.dynamic(light: 0xB76A22, dark: 0xF0B266)
    static let danger = Color.dynamic(light: 0xB83F4A, dark: 0xFF8992)
}

private extension Color {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct CodexPanelModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(reduceTransparency ? CodexPalette.raised : CodexPalette.surface.opacity(0.92))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CodexPalette.line.opacity(0.72), lineWidth: 0.5)
            }
    }
}

extension View {
    func codexPanel(padding: CGFloat = 16) -> some View {
        modifier(CodexPanelModifier(padding: padding))
    }

    func codexDisplayTitle() -> some View {
        font(.system(.title2, design: .rounded, weight: .bold))
            .foregroundStyle(CodexPalette.ink)
    }
}
