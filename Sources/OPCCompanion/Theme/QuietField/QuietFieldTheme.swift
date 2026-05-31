import SwiftUI
import AppKit

@MainActor
public struct QuietFieldTheme: Theme {
    public let id: ThemeID = .quietField

    public var background: AnyView { AnyView(QuietFieldBackground()) }

    public var bubbleUserStyle: AnyShapeStyle {
        AnyShapeStyle(Color(nsColor: Self.userBubbleDynamic))
    }

    public var bubbleAssistantStyle: AnyShapeStyle {
        AnyShapeStyle(Color(nsColor: Self.assistantBubbleDynamic))
    }

    private static let userBubbleDynamic: NSColor = NSColor(name: "QuietFieldUserBubble") { appearance in
        let dark = Self.isDark(appearance)
        return dark
            ? NSColor(red: 0.22, green: 0.20, blue: 0.17, alpha: 0.92)
            : NSColor(red: 0.86, green: 0.80, blue: 0.69, alpha: 0.72)
    }

    private static let assistantBubbleDynamic: NSColor = NSColor(name: "QuietFieldAssistantBubble") { appearance in
        let dark = Self.isDark(appearance)
        return dark
            ? NSColor(red: 0.075, green: 0.080, blue: 0.082, alpha: 0.82)
            : NSColor(red: 0.96, green: 0.94, blue: 0.90, alpha: 0.72)
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
            .map { $0 == .darkAqua || $0 == .vibrantDark } ?? false
    }

    public var accent: Color { Color(hex: "#9E3F35") }
    public var ink: Color    { Color(hex: "#2F3A3A") }
    public var gold: Color   { Color(hex: "#B89355") }

    public var textPrimary: Color   { Color.primary.opacity(0.95) }
    public var textSecondary: Color { Color.secondary.opacity(0.72) }
    public var textTertiary: Color  { Color.secondary.opacity(0.46) }

    public var titleFont: Font     { .system(size: 13, weight: .semibold) }
    public var bodyFont: Font      { .system(size: 15) }
    public var monoFont: Font      { .system(size: 11, design: .monospaced) }
    public var timestampFont: Font { .system(size: 10, design: .monospaced) }
    public var systemMsgFont: Font { .system(size: 11, weight: .medium) }
    public var latinFont: Font     { .custom("New York", size: 13).italic() }
    public var strongFont: Font    { .system(size: 15, weight: .semibold) }

    public var panelCornerRadius: CGFloat  { 12 }
    public var bubbleCornerRadius: CGFloat { 10 }
    public var inputCornerRadius: CGFloat  { 10 }

    public var panelEntrance: Animation { .easeOut(duration: 0.28) }
    public var entranceStaggerDelay: Double { 0.06 }

    public var systemPromptAppendix: String {
        """

        # Quiet Field Persona
        你是 OPC 伴侣的「静场」模式：一个思绪整理员，不是朋友、导师或教练。

        ## 语气
        - 中文，短句
        - 不安慰，不喊口号，不预测未来
        - 不把所有东西变成任务
        - 每次只给一个可控动作

        ## 回复合同
        普通回复最多包含三行：
        观察：一句话
        动作：一个下一步
        出口：记录 / 开始 / 推迟 / 删除 / 无动作

        ## 边界
        - 需要写 Notion、删除内容、结束会话时必须明确确认或调用对应工具
        - 如果提醒或建议可能过期，先承认需要重新检查当前状态
        - 当已经完成收束，不要继续追问
        """
    }

    public init() {}
}

struct QuietFieldBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            baseGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                Rectangle()
                    .fill(lineColor)
                    .frame(height: 0.5)
                    .padding(.horizontal, 28)
                    .padding(.top, 74)
                Spacer()
            }
            .allowsHitTesting(false)

            VStack {
                Spacer()
                HStack {
                    Rectangle()
                        .fill(Color(hex: "#B89355").opacity(colorScheme == .dark ? 0.22 : 0.30))
                        .frame(width: 84, height: 1)
                    Spacer()
                    Rectangle()
                        .fill(Color(hex: "#9E3F35").opacity(0.62))
                        .frame(width: 1.5, height: 18)
                        .rotationEffect(.degrees(6))
                }
                .padding(.horizontal, 34)
                .padding(.bottom, 70)
            }
            .allowsHitTesting(false)
        }
    }

    private var baseGradient: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(
                colors: [Color(hex: "#111315"), Color(hex: "#090A0B")],
                startPoint: .top,
                endPoint: .bottom
            )
            : LinearGradient(
                colors: [Color(hex: "#F4F0E8"), Color(hex: "#E6E1D7")],
                startPoint: .top,
                endPoint: .bottom
            )
    }

    private var lineColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.10)
    }
}
