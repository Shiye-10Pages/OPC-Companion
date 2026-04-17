import SwiftUI

// MARK: - 颜色系统（macOS 26 Liquid Glass 风格：跟随系统 accentColor，不硬编码色值）

struct AppColors {
    /// 主强调色：跟随用户在系统偏好设置中选择的 accentColor
    static let primary = Color.accentColor

    /// 不再使用渐变；Liquid Glass 风格偏好单色 + 材质叠加
    static let primaryGradient = LinearGradient(
        colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
        startPoint: .leading,
        endPoint: .trailing
    )

    // 气泡背景：用材质而非实底色
    static let userBubble = Color.accentColor.opacity(0.15)
    static let assistantBubble = Color(nsColor: .controlBackgroundColor).opacity(0.4)
    static let systemBubble = Color.orange.opacity(0.1)

    // 卡片 / 输入框
    static let inputBackground = Color(nsColor: .controlBackgroundColor).opacity(0.4)
    static let cardBackground = Color(nsColor: .controlBackgroundColor).opacity(0.3)
    static let cardBorder = Color(nsColor: .separatorColor).opacity(0.3)

    // 任务状态色（系统语义色，自动适配浅/深色）
    static let taskPending = Color.secondary
    static let taskInProgress = Color(nsColor: .systemGreen)
    static let taskDone = Color(nsColor: .systemBlue)
    static let taskCancelled = Color(nsColor: .systemRed)

    // 连接状态
    static let statusOk = Color(nsColor: .systemGreen)
    static let statusError = Color(nsColor: .systemRed)
}

// MARK: - 圆角系统（对齐 macOS 26 系统窗口 / sheet）

struct AppCornerRadius {
    static let panel: CGFloat = 16
    static let card: CGFloat = 12
    static let bubble: CGFloat = 14      // 从 18 降低，更接近系统消息
    static let button: CGFloat = 8
    static let input: CGFloat = 10
    static let overlay: CGFloat = 14     // 所有浮层 overlay 统一
}

// MARK: - 阴影系统（Liquid Glass 下阴影更淡、更扩散）

struct AppShadows {
    static let panel = ShadowStyle(color: .black.opacity(0.1), radius: 24, x: 0, y: 10)
    static let card = ShadowStyle(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    static let bubble = ShadowStyle(color: .black.opacity(0.03), radius: 4, x: 0, y: 1)
    static let overlay = ShadowStyle(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
}

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - 字体系统（语义化，跟随系统 Dynamic Type）

struct AppTypography {
    static let title = Font.headline
    static let body = Font.body
    static let caption = Font.caption
    static let timestamp = Font.caption  // 最小字号 11pt，不用 caption2
    static let code = Font.system(size: 13, design: .monospaced)
}

// MARK: - 动画系统（Spring-based，macOS 26 风格）

struct AppAnimations {
    static let quick = Animation.spring(duration: 0.2, bounce: 0.15)
    static let standard = Animation.spring(duration: 0.3, bounce: 0.12)
    static let smooth = Animation.spring(duration: 0.35, bounce: 0.2)
    static let bouncy = Animation.spring(duration: 0.4, bounce: 0.3)
}

// MARK: - 统一材质（overlay / popover / card 等重复使用的玻璃背景）

struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = AppCornerRadius.overlay

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(
                color: AppShadows.overlay.color,
                radius: AppShadows.overlay.radius,
                x: AppShadows.overlay.x,
                y: AppShadows.overlay.y
            )
    }
}

extension View {
    func glassBackground(cornerRadius: CGFloat = AppCornerRadius.overlay) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }
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
