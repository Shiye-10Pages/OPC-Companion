import Foundation

/// 通过 macOS Shortcuts CLI 切换系统 Focus / 勿扰。
/// 用户需要在"快捷指令" App 预先创建两个快捷指令：
///   - 「OPC Focus On」  — 开启指定的 Focus（如"工作"）
///   - 「OPC Focus Off」 — 关闭所有 Focus
/// 没配置也不报错，silent fallback。
public actor FocusModeService {
    public static let shared = FocusModeService()

    public enum Shortcut: String {
        case on = "OPC Focus On"
        case off = "OPC Focus Off"
    }

    private var isRunningTests: Bool { NSClassFromString("XCTestCase") != nil }

    public func enable() async {
        await run(.on)
    }

    public func disable() async {
        await run(.off)
    }

    private func run(_ shortcut: Shortcut) async {
        guard !isRunningTests else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", shortcut.rawValue]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            // 异步轮询替代 waitUntilExit()，避免阻塞 actor 线程
            while process.isRunning {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if process.terminationStatus != 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                OPCLogger.shared.log(.warn, "focus", "shortcuts \(shortcut.rawValue) exit \(process.terminationStatus): \(output)")
            }
        } catch {
            OPCLogger.shared.log(.warn, "focus", "shortcuts run \(shortcut.rawValue) failed: \(error.localizedDescription)")
        }
    }
}
