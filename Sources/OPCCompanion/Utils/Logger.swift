import Foundation
import Darwin

public enum LogLevel: String, Sendable {
    case debug = "DEBUG"
    case info  = "INFO"
    case warn  = "WARN"
    case error = "ERROR"
}

/// 全局日志：同时写到 `~/.opc-companion/logs/YYYY-MM-DD.log` 和 stderr。
/// NSLock 序列化写入。signal handler 用 async-signal-safe write(2) 直接写 fd。
public final class OPCLogger: @unchecked Sendable {
    public static let shared = OPCLogger()

    private let lock = NSLock()
    private let fileFormatter: DateFormatter
    private let tsFormatter: DateFormatter
    private var cachedFD: Int32 = -1
    private var cachedDay: String = ""

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

        // error 级别 → fire-and-forget 上报 Notion Error Logs DB
        if level == .error {
            reportToNotion(level: level, category: category, message: message, file: file, line: line)
        }
    }

    // MARK: - Notion 上报（fire-and-forget）

    private static let notionErrorDBId = "585ef8ff17d54ff095240c477b6c74ba"

    private func reportToNotion(level: LogLevel, category: String, message: String, file: String, line: Int) {
        // 不加锁、不阻塞。如果 token 没配就跳过。
        Task.detached(priority: .utility) {
            let token = CredentialCache.shared.getNotionToken()
            guard !token.isEmpty else { return }

            let title = "[\(level.rawValue)] \(category) — \(message.prefix(60))"
            let now = ISO8601DateFormatter().string(from: Date())
            let properties: [String: Any] = [
                "标题": ["title": [["text": ["content": String(title)]]]],
                "时间": ["date": ["start": now]],
                "级别": ["select": ["name": level.rawValue]],
                "类别": ["rich_text": [["text": ["content": category]]]],
                "消息": ["rich_text": [["text": ["content": String(message.prefix(2000))]]]],
                "状态": ["select": ["name": "未处理"]],
                "source_file": ["rich_text": [["text": ["content": "\(file):\(line)"]]]]
            ]

            guard let data = try? JSONSerialization.data(withJSONObject: properties) else { return }
            _ = try? await NotionService.shared.createPage(
                databaseId: Self.notionErrorDBId,
                propertiesData: data
            )
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

        let sigs: [Int32] = [SIGTRAP, SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE]
        for sig in sigs {
            signal(sig) { received in
                // signal handler 里不能用大部分 Foundation API；直接 write 到 stderr + 日志文件
                let path = OPCLogger.currentLogPath()
                let msg = "\n[CRASH] signal=\(received) \(Date())\n"
                path.withCString { cpath in
                    let fd = open(cpath, O_WRONLY | O_CREAT | O_APPEND, 0o600)
                    if fd >= 0 {
                        msg.withCString { cmsg in
                            _ = write(fd, cmsg, strlen(cmsg))
                        }
                        close(fd)
                    }
                }
                msg.withCString { cmsg in
                    _ = write(STDERR_FILENO, cmsg, strlen(cmsg))
                }
                _exit(128 &+ received)
            }
        }
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
