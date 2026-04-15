import AppKit

print("Main: Starting application...")

// 创建 delegate
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate

// 确保 delegate 被正确设置
print("Main: Delegate set to \(NSApplication.shared.delegate)")

// 运行应用
let result = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
print("Main: NSApplicationMain returned \(result)")
