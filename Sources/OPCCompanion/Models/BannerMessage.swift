import Foundation

public struct BannerMessage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let kind: Kind
    /// 可选 action：点击 banner 时触发。BannerView 按 action 渲染按钮并调对应 AppState 方法。
    /// 用 enum 而非 closure 以保持 Sendable。
    public let action: Action?

    public enum Kind: String, Sendable, CaseIterable {
        case info
        case success
        case warning
        case error
    }

    public enum Action: String, Sendable, Equatable {
        case openMorningRitual  // 点击后弹出早晨仪式（条件过期则不动）
        case undoBatchDelete    // 恢复刚才批量删除的随手记（5s 内有效）
        case openShiyeAIResources
    }

    public init(id: UUID = UUID(), text: String, kind: Kind = .info, action: Action? = nil) {
        self.id = id
        self.text = text
        self.kind = kind
        self.action = action
    }
}
