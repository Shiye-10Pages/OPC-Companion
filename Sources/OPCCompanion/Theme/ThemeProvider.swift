import SwiftUI
import Combine

/// 主题分发器：根据 AppState.config.themeID 解析当前 Theme
@MainActor
public final class ThemeProvider: ObservableObject {
    public static let shared = ThemeProvider()

    @Published public private(set) var current: any Theme = AuroraTheme()

    private var cancellable: AnyCancellable?

    private init() {
        // 启动时从 AppState 配置同步
        bind()
    }

    public func bind() {
        let state = AppState.shared
        update(for: state.config.themeID)
        cancellable = state.$config
            .map(\.themeID)
            .removeDuplicates()
            .sink { [weak self] id in self?.update(for: id) }
    }

    public func update(for idString: String) {
        let id = ThemeID(rawValue: idString) ?? .aurora
        switch id {
        case .aurora: current = AuroraTheme()
        case .wabi:   current = AuroraTheme()    // 占位：本次仅 Aurora 完整实现
        case .flow:   current = AuroraTheme()    // 占位
        case .stoa:   current = StoaTheme()
        case .quietField: current = QuietFieldTheme()
        }
    }

    public func set(_ id: ThemeID) {
        var cfg = AppState.shared.config
        cfg.themeID = id.rawValue
        AppState.shared.config = cfg
        AppState.shared.saveConfig()
    }

    /// 把当前主题的 system prompt 附录拼到 base prompt 后。
    /// ChatEngine 不在 MainActor，所有需要发消息的调用方应通过此方法
    /// 在 MainActor 上下文里拼好 prompt 再传入。
    public func composedPrompt(base: String) -> String {
        let appendix = current.systemPromptAppendix
        if appendix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return base
        }
        return base + "\n\n" + appendix
    }
}

// MARK: - Environment Key

@MainActor
private struct ThemeKey: @preconcurrency EnvironmentKey {
    static let defaultValue: any Theme = DefaultTheme()
}

extension EnvironmentValues {
    @MainActor public var theme: any Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - View Modifier

extension View {
    /// 把当前 ThemeProvider.current 注入到子树
    public func withTheme(_ theme: any Theme) -> some View {
        environment(\.theme, theme)
    }
}
