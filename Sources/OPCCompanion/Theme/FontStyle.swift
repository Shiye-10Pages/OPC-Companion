import SwiftUI

// MARK: - FontStyle 字体方案
//
// 设计原则：4 套字体方案，与主题色系（Aurora/Stoa）正交。
// 默认套以「可读性」为最高优先；其余 3 套为「精致感 / 艺术性」导向，
// 各自呼应不同的产品调性，用户可在设置页自由切换。
//
// 实现方式：每套返回一个 FontStyleSet 结构，包含 7 类字体角色。
// View 通过 @Environment(\.fontStyle) 拿到当前 set；ChatView / MessageBubble /
// MainTabView 等核心 view 用 fontStyle.bodyFont / titleFont 等替代 theme.bodyFont。
// Theme 协议的字体属性保留作为 fallback，不再被主路径使用。

public enum FontStyleID: String, CaseIterable, Codable, Sendable {
    case readable      // 可读：苹方（系统中文）+ SF Pro（系统英文）— 默认
    case rounded       // 圆润：SF Pro Rounded + 苹方 SC Light — Aurora 极光气质
    case serif         // 衬线：New York Serif + 苹方 SC — Stoa 古典文人气质
    case display       // 紧致：SF Pro Display Semibold + 苹方 Heavy — 高密度信息密度

    public var displayName: String {
        switch self {
        case .readable: return "可读优先"
        case .rounded:  return "圆润现代"
        case .serif:    return "衬线古典"
        case .display:  return "紧致密度"
        }
    }

    public var subtitle: String {
        switch self {
        case .readable: return "苹方 + SF Pro · 默认 · 最佳可读性"
        case .rounded:  return "SF Pro Rounded · 友好 · 配 Aurora"
        case .serif:    return "New York Serif · 文人 · 配 Stoa"
        case .display:  return "SF Pro Display · 紧致 · 高密度信息"
        }
    }

    /// 字体方案与主题色系的推荐组合（仅作 picker 的「推荐」提示，不强制）
    public var recommendedFor: [ThemeID] {
        switch self {
        case .readable: return ThemeID.allCases   // 通用
        case .rounded:  return [.aurora]
        case .serif:    return [.stoa]
        case .display:  return [.flow, .aurora]
        }
    }
}

// MARK: - FontStyleSet

public struct FontStyleSet: Sendable {
    public var id: FontStyleID
    public var bodyFont: Font
    public var titleFont: Font
    public var monoFont: Font
    public var timestampFont: Font
    public var systemMsgFont: Font
    public var strongFont: Font
    public var latinFont: Font

    public static func from(_ id: FontStyleID) -> FontStyleSet {
        switch id {
        case .readable:
            return FontStyleSet(
                id: id,
                bodyFont:      .system(size: 15, weight: .regular),
                titleFont:     .system(size: 13, weight: .medium),
                monoFont:      .system(size: 11, design: .monospaced),
                timestampFont: .system(size: 10, design: .monospaced),
                systemMsgFont: .system(size: 11, weight: .medium),
                strongFont:    .system(size: 15, weight: .semibold),
                latinFont:     .system(size: 13, design: .serif).italic()
            )

        case .rounded:
            return FontStyleSet(
                id: id,
                bodyFont:      .system(size: 15, weight: .regular, design: .rounded),
                titleFont:     .system(size: 13, weight: .medium, design: .rounded),
                monoFont:      .system(size: 11, design: .monospaced),
                timestampFont: .system(size: 10, weight: .regular, design: .rounded),
                systemMsgFont: .system(size: 11, weight: .medium, design: .rounded),
                strongFont:    .system(size: 15, weight: .semibold, design: .rounded),
                latinFont:     .system(size: 13, design: .serif).italic()
            )

        case .serif:
            return FontStyleSet(
                id: id,
                bodyFont:      .custom("New York", size: 15).leading(.standard),
                titleFont:     .custom("New York Small", size: 13).weight(.medium),
                monoFont:      .system(size: 11, design: .monospaced),
                timestampFont: .custom("New York Small", size: 10),
                systemMsgFont: .custom("New York Small", size: 11),
                strongFont:    .custom("New York", size: 15).weight(.semibold),
                latinFont:     .custom("New York Italic", size: 13).italic()
            )

        case .display:
            return FontStyleSet(
                id: id,
                bodyFont:      .system(size: 14.5, weight: .regular, design: .default),
                titleFont:     .system(size: 13, weight: .semibold, design: .default),
                monoFont:      .system(size: 11, design: .monospaced),
                timestampFont: .system(size: 10, weight: .medium, design: .monospaced),
                systemMsgFont: .system(size: 11, weight: .semibold),
                strongFont:    .system(size: 15, weight: .heavy, design: .default),
                latinFont:     .system(size: 13, design: .serif).italic()
            )
        }
    }
}

// MARK: - Environment

private struct FontStyleKey: EnvironmentKey {
    static let defaultValue: FontStyleSet = FontStyleSet.from(.readable)
}

extension EnvironmentValues {
    public var fontStyle: FontStyleSet {
        get { self[FontStyleKey.self] }
        set { self[FontStyleKey.self] = newValue }
    }
}

// MARK: - ColorScheme

public enum ColorSchemeOverride: String, CaseIterable, Sendable {
    case system, light, dark

    public var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "白天模式"
        case .dark:   return "黑夜模式"
        }
    }

    public var resolved: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
