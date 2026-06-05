import Foundation

/// 一条可用更新的信息（来自线上 version.json）。
public struct UpdateInfo: Equatable, Sendable {
    public let version: String
    public let notes: String
    public let installCmd: String
    public let url: String
}

/// 版本更新检查：拉取线上 `version.json`（安装分支的 raw），与本地 stamp 的版本比对。
/// 发现新版 → 写入 `AppState.availableUpdate` 并（每个版本仅一次）弹一条提示横幅。
/// 真相源是 version.json：dev 改完顺手 bump 一个数字、提交即可，零发版仪式。
public final class UpdateService: @unchecked Sendable {
    public static let shared = UpdateService()

    static let manifestURL = URL(string: "https://raw.githubusercontent.com/Shiye-10Pages/OPC-Companion/refs/heads/feature/focused-conversation-memory/version.json")!
    private static let minInterval: TimeInterval = 6 * 3600   // 节流：最多每 6 小时自动查一次
    private static let notifiedKey = "lastNotifiedUpdateVersion"

    private let lock = NSLock()
    private var lastCheckAt: Date?
    private var inFlight = false

    /// 启动 / 定时调用。内部节流，常驻 app 每 60s ping 也只会真正查 6 小时一次。
    public func checkInBackground(force: Bool = false) {
        lock.lock()
        if inFlight { lock.unlock(); return }
        if !force, let last = lastCheckAt, Date().timeIntervalSince(last) < Self.minInterval {
            lock.unlock(); return
        }
        inFlight = true
        lock.unlock()

        Task { [weak self] in
            guard let self else { return }
            defer { self.endFlight() }
            guard let info = await self.fetch() else { return }
            let outdated = AppVersion.isOlder(AppVersion.current, than: info.version)
            await MainActor.run {
                AppState.shared.availableUpdate = outdated ? info : nil
                // 开发态（未 stamp）不打扰；每个版本只主动横幅一次
                guard outdated, !AppVersion.isDevBuild else { return }
                if UserDefaults.standard.string(forKey: Self.notifiedKey) != info.version {
                    UserDefaults.standard.set(info.version, forKey: Self.notifiedKey)
                    AppState.shared.showBanner(
                        "发现新版本 v\(info.version) · 到设置页可一键复制更新命令",
                        kind: .info,
                        duration: 8.0
                    )
                }
            }
        }
    }

    /// 设置页「检查更新」用：强制查并返回一句结果文案。
    public func checkNow() async -> String {
        guard let info = await fetch() else { return "检查失败，请检查网络后重试" }
        let outdated = AppVersion.isOlder(AppVersion.current, than: info.version)
        await MainActor.run { AppState.shared.availableUpdate = outdated ? info : nil }
        return outdated ? "发现新版本 v\(info.version)" : "已是最新版本 v\(AppVersion.current)"
    }

    private func endFlight() {
        lock.lock(); inFlight = false; lastCheckAt = Date(); lock.unlock()
    }

    private func fetch() async -> UpdateInfo? {
        var req = URLRequest(url: Self.manifestURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                logError("update", "manifest http \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = (obj["version"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !version.isEmpty else {
                logError("update", "manifest parse failed")
                return nil
            }
            return UpdateInfo(
                version: version,
                notes: (obj["notes"] as? String) ?? "",
                installCmd: (obj["install_cmd"] as? String) ?? "",
                url: (obj["url"] as? String) ?? "https://github.com/Shiye-10Pages/OPC-Companion"
            )
        } catch {
            logError("update", "manifest fetch error: \(LogRedactor.redact(error.localizedDescription))")
            return nil
        }
    }
}
