import SwiftUI

// MARK: - Theme ID

public enum ThemeID: String, CaseIterable, Codable {
    case aurora
    case wabi
    case flow
    case stoa
    case quietField

    public var displayName: String {
        switch self {
        case .aurora: return "极光 Aurora"
        case .wabi:   return "侘寂 Wabi"
        case .flow:   return "心流 Flow"
        case .stoa:   return "斯多葛 Stoa"
        case .quietField: return "静场 Quiet Field"
        }
    }

    public var heroTitle: String {
        switch self {
        case .aurora: return "When skin meets soul."
        case .wabi:   return "殘缺亦完。"
        case .flow:   return "Less. Sharper. Now."
        case .stoa:   return "A mirror, not a maid."
        case .quietField: return "A field, not a feed."
        }
    }

    public var tagline: String {
        switch self {
        case .aurora: return "视觉锤。打磨到截图即传播。"
        case .wabi:   return "朱砂落款 · 古文體 AI · 接受未完成。"
        case .flow:   return "减一切冗余，AI 主动校准你的挑战难度。"
        case .stoa:   return "AI 不替你做事，它把事情拆开给你看。"
        case .quietField: return "少说、短句、可收束。让思绪有边界。"
        }
    }
}

// MARK: - Theme Protocol

/// 主题协议：每个主题提供完整的视觉 token + AI 行为 prompt
@MainActor
public protocol Theme {
    var id: ThemeID { get }

    // 颜色
    var background: AnyView { get }          // 主题背景视图（含动画、mesh、blob 等）
    var bubbleUserStyle: AnyShapeStyle { get }
    var bubbleAssistantStyle: AnyShapeStyle { get }
    var accent: Color { get }                // 强调色（Aurora 玫瑰粉 / Stoa 朱砂）
    var ink: Color { get }                   // 第二语义色（Stoa 墨蓝）
    var gold: Color { get }                  // 第三语义色（Stoa 暖金，拉丁词）
    var textPrimary: Color { get }
    var textSecondary: Color { get }
    var textTertiary: Color { get }

    // 字体
    var titleFont: Font { get }
    var bodyFont: Font { get }
    var monoFont: Font { get }
    var timestampFont: Font { get }
    var systemMsgFont: Font { get }
    var latinFont: Font { get }              // 拉丁词专用（New York Italic）
    var strongFont: Font { get }             // **加粗** 强调字（SF Pro Display + 紧字距 / 衬线 bold 等）

    // 形状
    var panelCornerRadius: CGFloat { get }
    var bubbleCornerRadius: CGFloat { get }
    var inputCornerRadius: CGFloat { get }

    // 入场动画
    var panelEntrance: Animation { get }
    var entranceStaggerDelay: Double { get }

    // AI 行为：system prompt（落 ChatEngine 用）
    var systemPromptAppendix: String { get }
}

// MARK: - Default 兜底

@MainActor
public struct DefaultTheme: Theme {
    public let id: ThemeID = .aurora
    public var background: AnyView { AnyView(Color.black.opacity(0.02)) }
    public var bubbleUserStyle: AnyShapeStyle { AnyShapeStyle(Color.accentColor) }
    public var bubbleAssistantStyle: AnyShapeStyle { AnyShapeStyle(Color.gray.opacity(0.15)) }
    public var accent: Color { .accentColor }
    public var ink: Color { Color(red: 0.29, green: 0.40, blue: 0.64) }
    public var gold: Color { Color(red: 0.79, green: 0.64, blue: 0.42) }
    public var textPrimary: Color { .primary }
    public var textSecondary: Color { .secondary }
    public var textTertiary: Color { Color.secondary.opacity(0.65) }
    public var titleFont: Font { .system(size: 14, weight: .semibold) }
    public var bodyFont: Font { .system(size: 14) }
    public var monoFont: Font { .system(size: 11, design: .monospaced) }
    public var timestampFont: Font { .system(size: 10, design: .monospaced) }
    public var systemMsgFont: Font { .system(size: 11) }
    public var latinFont: Font { .system(size: 13, design: .serif).italic() }
    public var strongFont: Font { .system(size: 15, weight: .semibold) }
    public var panelCornerRadius: CGFloat { 20 }
    public var bubbleCornerRadius: CGFloat { 18 }
    public var inputCornerRadius: CGFloat { 12 }
    public var panelEntrance: Animation { .easeOut(duration: 0.4) }
    public var entranceStaggerDelay: Double { 0.12 }
    public var systemPromptAppendix: String { "" }

    public init() {}
}
