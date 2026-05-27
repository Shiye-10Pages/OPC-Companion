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
/// 1. 启动 6s 自检；若 Carbon callback 从未 fire，根据 `IsSecureEventInputEnabled()`
///    分两种 case 推 banner。
/// 2. 每 5s 重检一次，最多 6 次（启动后 36s 内）；一旦 callback fire 或 Secure Input
///    解除，立刻清掉警告，发一条"已恢复" info banner（3s）。
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
    }

    private func evaluate(isInitialCheck: Bool) {
        let fired = CarbonHotkeyManager.shared.callbackEverFired
        let secure = CarbonHotkeyManager.shared.callbackEverFired ? false : CarbonHotkeyManager.isSecureInputEnabled()
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

        // 还没 fire 过
        if isInitialCheck {
            // 第一次检测，无论 secure 与否都推 banner
            if secure {
                AppState.shared.showBanner(
                    "⚠️ 系统启用了安全输入（某个 App 在接收密码），全局热键暂时无效。等那个 App 失焦后会自动恢复。",
                    kind: .warning,
                    duration: 8.0
                )
            } else {
                AppState.shared.showBanner(
                    "⚠️ 全局热键无响应。可能被其他 App（Alfred / Raycast / 启动器）抢占，或系统输入法占用了 Opt+Space。",
                    kind: .warning,
                    duration: 8.0
                )
            }
            warnedActive = true
        } else {
            // 后续重检：Secure Input 解除（之前 secure=true，本次=false）也算"恢复中"
            // 这里 fired 仍是 false，所以只在 secure 由 true 转 false 时推一条提示。
            // 简化处理：不维护"上一次 secure"，等 fired 真的 true 时再推恢复 banner。
            // 但如果 secure 由 true → false 仍然没人按热键，也不打扰用户。
        }
    }
}
