import AppKit

// 第一件事：安装崩溃捕获，以便后续任何阶段的异常/信号都进日志
OPCLogger.shared.installCrashHandler()
logInfo("main", "OPCCompanion starting")

// 补传上次崩溃遗留的 pending-crashes.jsonl 到 Notion Error Logs DB。
// 无 token / 文件不存在 → 内部静默跳过，不阻塞主流程。
Task.detached(priority: .utility) {
    await OPCLogger.shared.drainPendingCrashes()
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
logInfo("main", "Delegate set")

let result = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
logInfo("main", "NSApplicationMain returned \(result)")
