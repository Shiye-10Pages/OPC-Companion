import Foundation
import Carbon.HIToolbox

/// 全局热键健康监视器。
///
/// 背景（见 `.bug-investigations/2026-05-27-hotkey-failure.md`）：
/// - 历史现象「启动后无效 → 几分钟后突然好用」最可能是 macOS Secure Event Input
///   抢占了第三方全局热键。Secure Input 由外部进程触发（终端 sudo / 密码字段 等），
///   App 无法直接消除，只能监测 + 提示用户。
///
/// 监视策略：
/// 1. 启动 6s 自检；仅当 `IsSecureEventInputEnabled()` 明确为 true 时推 warning banner。
/// 2. 每 5s 重检一次，最多 6 次（启动后 36s 内）；一旦 callback fire 或 Secure Input
///    解除，立刻清掉警告，发一条"已恢复" info banner（3s）。
/// 3. callback 从未 fire 只能说明用户还没按过热键，不能据此判断热键失效。
@MainActor
final class HotkeyHealthMonitor {
    static let shared = HotkeyHealthMonitor()

    private var task: Task<Void, Never>?
    /// 上一次 banner 是否处于 warning 态（用来决定是否在恢复时推 info banner）
    private var warnedActive = false

    private init() {}

    /// AppDelegate 在 setupHotkey() 末尾调用一次即可。
    func start() {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            // 启动 6s 自检
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            self?.evaluate(isInitialCheck: true)

            // 之后每 5s 重检一次，最多 6 次
            for _ in 0..<6 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                self?.evaluate(isInitialCheck: false)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// 当 callbackEverFired 状态改变时（首次 fire）调用，确保 banner 能即时清除。
    func notifyCallbackFired() {
        if warnedActive {
            warnedActive = false
            AppState.shared.showBanner("全局热键已恢复", kind: .success, duration: 3.0)
        }
        stop()
    }

    private func evaluate(isInitialCheck: Bool) {
        let fired = CarbonHotkeyManager.shared.callbackEverFired
        let secure = CarbonHotkeyManager.isSecureInputEnabled()
        OPCLogger.shared.log(
            .info,
            "hotkey",
            "[secure-input] check fired=\(fired) enabled=\(secure)"
        )

        if fired {
            // 已恢复（之前没 fire 过、现在 fire 了）
            if warnedActive {
                warnedActive = false
                AppState.shared.showBanner("全局热键已恢复", kind: .success, duration: 3.0)
            }
            stop()
            return
        }

        if secure {
            if !warnedActive {
                AppState.shared.showBanner(
                    "⚠️ 系统启用了安全输入（某个 App 在接收密码），全局热键暂时无效。等那个 App 失焦后会自动恢复。",
                    kind: .warning,
                    duration: 8.0
                )
            }
            warnedActive = true
            return
        }

        if warnedActive {
            warnedActive = false
            AppState.shared.showBanner("全局热键已恢复", kind: .success, duration: 3.0)
            stop()
        } else if isInitialCheck {
            OPCLogger.shared.log(.info, "hotkey", "[secure-input] no blocking evidence; keep monitoring silently")
        }
    }
}
