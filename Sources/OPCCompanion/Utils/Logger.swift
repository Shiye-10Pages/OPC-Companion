import Foundation
import Darwin

public enum LogLevel: String, Sendable {
    case debug = "DEBUG"
    case info  = "INFO"
    case warn  = "WARN"
    case error = "ERROR"
}

/// 全局日志：同时写到 `~/.opc-companion/logs/YYYY-MM-DD.log` 和 stderr。
/// NSLock 序列化写入。signal handler 全程只用 async-signal-safe 调用（open/write/close/_exit
/// + 栈缓冲），路径与前缀在安装时预计算，绝不在信号上下文里碰 Foundation 或分配堆内存。
public final class OPCLogger: @unchecked Sendable {
    public static let shared = OPCLogger()

    private let lock = NSLock()
    private let fileFormatter: DateFormatter
    private let tsFormatter: DateFormatter
    private var cachedFD: Int32 = -1
    private var cachedDay: String = ""

    // 崩溃 handler 专用：不可变全局常量（Sendable 安全），handler 内只读不分配、不触发初始化。
    // 路径在首次访问（安装时）定格为当天日志文件：跨午夜后的崩溃会写进安装当天的文件，可接受
    //（崩溃低频，signal-safe 优先于日期精确）。
    private static let crashLogPathC: ContiguousArray<CChar> = ContiguousArray(OPCLogger.currentLogPath().utf8CString)
    private static let crashPrefixBytes: [UInt8] = Array("\n[CRASH] signal=".utf8)

    private init() {
        fileFormatter = DateFormatter()
        fileFormatter.dateFormat = "yyyy-MM-dd"
        fileFormatter.locale = Locale(identifier: "en_US_POSIX")
        fileFormatter.timeZone = TimeZone.current

        tsFormatter = DateFormatter()
        tsFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        tsFormatter.locale = Locale(identifier: "en_US_POSIX")
        tsFormatter.timeZone = TimeZone.current
    }

    public func log(
        _ level: LogLevel,
        _ category: String,
        _ message: String,
        file: String = #fileID,
        line: Int = #line
    ) {
        let now = Date()
        let ts = tsFormatter.string(from: now)
        let short = (file as NSString).lastPathComponent
        let lineStr = "[\(ts)] [\(level.rawValue)] [\(category)] \(short):\(line) \(message)\n"

        lock.lock()
        let fd = ensureFileDescriptor(for: now)
        if fd >= 0, let data = lineStr.data(using: .utf8) {
            data.withUnsafeBytes { buf in
                _ = write(fd, buf.baseAddress, buf.count)
            }
        }
        lock.unlock()

        // stderr：开发阶段方便在 launcher 输出里看到
        if let data = lineStr.data(using: .utf8) {
            data.withUnsafeBytes { buf in
                _ = write(STDERR_FILENO, buf.baseAddress, buf.count)
            }
        }

    }

    /// 返回当日日志文件路径（已保证父目录存在）。
    public static func currentLogPath() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".opc-companion/logs/\(f.string(from: Date())).log").path
    }

    /// 安装崩溃捕获：Objective-C 异常 + POSIX 信号。仅调用一次。
    public func installCrashHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.joined(separator: "\n  ")
            let msg = "Uncaught NSException: \(exception.name.rawValue) reason=\(exception.reason ?? "nil")\n  \(stack)"
            OPCLogger.shared.log(.error, "crash", msg)
        }

        // 在安装时（非信号上下文）强制完成惰性初始化，确保 signal handler 内只命中已初始化的只读值。
        _ = OPCLogger.crashLogPathC
        _ = OPCLogger.crashPrefixBytes

        let sigs: [Int32] = [SIGTRAP, SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE]
        for sig in sigs {
            signal(sig) { received in
                // 闭包不捕获任何局部变量（@convention(c) 要求）；只调 async-signal-safe 函数。
                // 不碰任何 Foundation（DateFormatter/Date/String 插值会分配或加锁，可能二次死锁丢日志）。
                OPCLogger.crashLogPathC.withUnsafeBufferPointer { p in
                    if let base = p.baseAddress {
                        let fd = open(base, O_WRONLY | O_CREAT | O_APPEND, 0o600)
                        if fd >= 0 {
                            OPCLogger.emitCrashLine(fd, received)
                            close(fd)
                        }
                    }
                }
                OPCLogger.emitCrashLine(STDERR_FILENO, received)
                _exit(128 &+ received)
            }
        }
    }

    /// 把 `\n[CRASH] signal=NN\n` 写到 fd —— 只用 async-signal-safe 调用 + 栈缓冲，不分配堆内存。
    private static func emitCrashLine(_ fd: Int32, _ sig: Int32) {
        crashPrefixBytes.withUnsafeBufferPointer { p in
            if let base = p.baseAddress { _ = write(fd, base, p.count) }
        }
        // 手动把 signal 号转十进制 ASCII，写进栈上临时缓冲（不分配堆内存）
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 16) { buf in
            var n = Int(sig)
            if n < 0 { n = 0 }
            var i = 16
            if n == 0 {
                i -= 1
                buf[i] = 0x30
            } else {
                while n > 0 {
                    i -= 1
                    buf[i] = UInt8(0x30 + (n % 10))
                    n /= 10
                }
            }
            if let base = buf.baseAddress { _ = write(fd, base + i, 16 - i) }
        }
        var nl: UInt8 = 0x0A
        _ = write(fd, &nl, 1)
    }

    // MARK: - Private

    private func ensureFileDescriptor(for date: Date) -> Int32 {
        let day = fileFormatter.string(from: date)
        if day == cachedDay, cachedFD >= 0 {
            return cachedFD
        }
        if cachedFD >= 0 { close(cachedFD); cachedFD = -1 }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".opc-companion/logs")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let path = dir.appendingPathComponent("\(day).log").path
        let fd = path.withCString { open($0, O_WRONLY | O_CREAT | O_APPEND, 0o600) }
        if fd >= 0 {
            cachedFD = fd
            cachedDay = day
        }
        return fd
    }
}

// MARK: - 便捷函数

public func logDebug(_ cat: String, _ msg: String, file: String = #fileID, line: Int = #line) {
    OPCLogger.shared.log(.debug, cat, msg, file: file, line: line)
}
public func logInfo(_ cat: String, _ msg: String, file: String = #fileID, line: Int = #line) {
    OPCLogger.shared.log(.info, cat, msg, file: file, line: line)
}
public func logWarn(_ cat: String, _ msg: String, file: String = #fileID, line: Int = #line) {
    OPCLogger.shared.log(.warn, cat, msg, file: file, line: line)
}
public func logError(_ cat: String, _ msg: String, file: String = #fileID, line: Int = #line) {
    OPCLogger.shared.log(.error, cat, msg, file: file, line: line)
}
