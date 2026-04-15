import SwiftUI

// MARK: - 颜色系统
struct AppColors {
    static let primary = Color(hex: "#007AFF")
    static let secondary = Color(hex: "#5E5CE6")

    static let primaryGradient = LinearGradient(
        colors: [primary, secondary],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let userBubble = Color(hex: "#007AFF").opacity(0.15)
    static let assistantBubble = Color(nsColor: .controlBackgroundColor)
    static let systemBubble = Color(hex: "#FFF3E0")

    static let inputBackground = Color(nsColor: .controlBackgroundColor).opacity(0.6)
    static let cardBackground = Color.white.opacity(0.5)
}

// MARK: - 圆角系统
struct AppCornerRadius {
    static let panel: CGFloat = 20
    static let card: CGFloat = 16
    static let bubble: CGFloat = 18
    static let button: CGFloat = 10
    static let input: CGFloat = 12
}

// MARK: - 阴影系统
struct AppShadows {
    static let panel = ShadowStyle(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
    static let card = ShadowStyle(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    static let bubble = ShadowStyle(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
}

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - 字体系统
struct AppTypography {
    static let title = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 14, weight: .regular)
    static let caption = Font.system(size: 12, weight: .regular)
    static let timestamp = Font.system(size: 10, weight: .regular)
    static let code = Font.system(size: 13, design: .monospaced)
}

// MARK: - 动画系统
struct AppAnimations {
    static let quick = Animation.easeInOut(duration: 0.2)
    static let standard = Animation.easeInOut(duration: 0.25)
    static let smooth = Animation.spring(response: 0.3, dampingFraction: 0.7)
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}