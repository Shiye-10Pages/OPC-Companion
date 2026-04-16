import AppKit

// 第一件事：安装崩溃捕获，以便后续任何阶段的异常/信号都进日志
OPCLogger.shared.installCrashHandler()
logInfo("main", "OPCCompanion starting")

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
logInfo("main", "Delegate set")

let result = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
logInfo("main", "NSApplicationMain returned \(result)")
