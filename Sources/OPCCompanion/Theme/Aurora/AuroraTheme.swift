import SwiftUI

@MainActor
public struct AuroraTheme: Theme {
    public let id: ThemeID = .aurora

    public var background: AnyView { AnyView(AuroraBackground()) }

    public var bubbleUserStyle: AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.66, blue: 0.79),   // 玫瑰粉 #F4A8C9
                    Color(red: 0.73, green: 0.54, blue: 0.88),   // 暖紫   #B98AE0
                    Color(red: 0.56, green: 0.44, blue: 0.83)    // 深紫   #8E6FD4
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    public var bubbleAssistantStyle: AnyShapeStyle {
        // panel 背景本身已是 ultraThinMaterial，气泡再叠 material 会双层穿透产生硬光斑。
        // 改为柔和淡色实底 + 极淡描边，让气泡跟 panel 明确分层。
        AnyShapeStyle(Color.white.opacity(0.42))
    }

    public var accent: Color  { Color(red: 0.91, green: 0.64, blue: 0.79) }   // E8A4C9
    public var ink: Color     { Color(red: 0.29, green: 0.40, blue: 0.64) }
    public var gold: Color    { Color(red: 0.79, green: 0.64, blue: 0.42) }

    public var textPrimary: Color   { Color.primary.opacity(0.96) }
    public var textSecondary: Color { Color.primary.opacity(0.62) }
    public var textTertiary: Color  { Color.primary.opacity(0.40) }

    // 字体（对应 demo CSS 中 Aurora 的精修层级）
    public var titleFont: Font     { .system(size: 13, weight: .medium, design: .rounded) }
    public var bodyFont: Font      { .system(size: 15) }
    public var monoFont: Font      { .system(size: 11, design: .monospaced) }
    public var timestampFont: Font { .system(size: 10, design: .monospaced) }
    public var systemMsgFont: Font { .system(size: 10.5, weight: .medium, design: .rounded) }
    public var latinFont: Font     { .custom("New York Italic", size: 13).italic() }
    /// 强调字：SF Pro Display + semibold + 紧字距（用于 markdown **bold** 和数字强调）
    public var strongFont: Font    { .system(size: 15, weight: .semibold, design: .default) }

    public var panelCornerRadius: CGFloat  { 26 }
    public var bubbleCornerRadius: CGFloat { 22 }
    public var inputCornerRadius: CGFloat  { 24 }

    public var panelEntrance: Animation { .spring(response: 0.55, dampingFraction: 0.78) }
    public var entranceStaggerDelay: Double { 0.12 }

    public var systemPromptAppendix: String {
        """

        # Aurora Persona
        你是 OPC 伴侣的「当下」模式。
        - 只关心用户「现在」的状态，不替他规划明天
        - 时间表述用相对时间（"刚才"、"3 分钟前"）
        - 不堆积——一次只处理一件事
        - 不安慰，不空头规划
        """
    }

    public init() {}
}
