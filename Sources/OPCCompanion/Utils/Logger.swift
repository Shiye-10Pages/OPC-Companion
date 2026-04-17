import Foundation
import Darwin

public enum LogLevel: String, Sendable {
    case debug = "DEBUG"
    case info  = "INFO"
    case warn  = "WARN"
    case error = "ERROR"
    case crash = "CRASH"
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

        // warn / error / crash 级别 → fire-and-forget 上报 Notion Error Logs DB
        switch level {
        case .warn, .error, .crash:
            reportToNotion(level: level, category: category, message: message, file: file, line: line)
        case .debug, .info:
            break
        }
    }

    // MARK: - Notion 上报（fire-and-forget）

    private static let notionErrorDBId = "585ef8ff17d54ff095240c477b6c74ba"

    /// LogLevel → Notion 级别 select 选项名。Notion 里定义的是小写，历史代码传了大写 rawValue
    /// 会被 Notion 视为新选项或 400，这里显式映射避免悄悄失败。
    private static func notionLevelName(_ level: LogLevel) -> String? {
        switch level {
        case .crash: return "crash"
        case .error: return "error"
        case .warn:  return "warning"
        case .debug, .info: return nil
        }
    }

    private func reportToNotion(level: LogLevel, category: String, message: String, file: String, line: Int) {
        guard let levelName = Self.notionLevelName(level) else { return }
        // 不加锁、不阻塞。如果 token 没配就跳过。
        Task.detached(priority: .utility) {
            let token = CredentialCache.shared.getNotionToken()
            guard !token.isEmpty else { return }

            let title = "[\(levelName)] \(category) — \(message.prefix(60))"
            let now = ISO8601DateFormatter().string(from: Date())
            let properties: [String: Any] = [
                "标题": ["title": [["text": ["content": String(title)]]]],
                "时间": ["date": ["start": now]],
                "级别": ["select": ["name": levelName]],
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

    /// 崩溃 sentinel 文件路径。signal handler 里 async-signal-safe 追加，
    /// 下次 app 启动由 drainPendingCrashes() 补传 Notion。
    public static func pendingCrashesPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".opc-companion/logs/pending-crashes.jsonl").path
    }

    /// 安装崩溃捕获：Objective-C 异常 + POSIX 信号。仅调用一次。
    public func installCrashHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.joined(separator: "\n  ")
            let msg = "Uncaught NSException: \(exception.name.rawValue) reason=\(exception.reason ?? "nil")\n  \(stack)"
            OPCLogger.shared.log(.crash, "crash", msg)
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

                // 同步落一行 JSONL 到 sentinel 文件，下次启动补传 Notion。
                // time(2) 是 async-signal-safe；避免 ISO8601Formatter 这类分配。
                let unixTime = time(nil)
                let sentinel = "{\"signal\":\(received),\"ts_unix\":\(unixTime)}\n"
                let pending = OPCLogger.pendingCrashesPath()
                pending.withCString { cpath in
                    let fd = open(cpath, O_WRONLY | O_CREAT | O_APPEND, 0o600)
                    if fd >= 0 {
                        sentinel.withCString { cmsg in
                            _ = write(fd, cmsg, strlen(cmsg))
                        }
                        close(fd)
                    }
                }

                _exit(128 &+ received)
            }
        }
    }

    /// 启动时调用。扫 sentinel 文件补传 Notion，成功则清空。
    /// 任一条失败就停止，保留文件等下次重试。无 token / 文件不存在 → 安静跳过。
    public func drainPendingCrashes() async {
        CredentialCache.shared.loadIfNeeded()
        let token = CredentialCache.shared.getNotionToken()
        guard !token.isEmpty else { return }

        let path = Self.pendingCrashesPath()
        guard let content = try? String(contentsOfFile: path, encoding: .utf8),
              !content.isEmpty else { return }

        let lines = content
            .split(whereSeparator: { $0 == "\n" })
            .map(String.init)
            .prefix(100) // 防失控文件拖死启动

        var allOK = true
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let sig = (dict["signal"] as? Int) ?? -1
            let tsUnix = (dict["ts_unix"] as? Int) ?? Int(Date().timeIntervalSince1970)
            let occurredAt = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(tsUnix)))
            let message = "signal=\(sig) signame=\(Self.signalName(sig))"

            let ok = await postCrashToNotion(message: message, occurredAt: occurredAt)
            if !ok { allOK = false; break }
        }

        if allOK {
            try? "".write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private func postCrashToNotion(message: String, occurredAt: String) async -> Bool {
        let title = "[crash] app — \(message.prefix(80))"
        let properties: [String: Any] = [
            "标题": ["title": [["text": ["content": title]]]],
            "时间": ["date": ["start": occurredAt]],
            "级别": ["select": ["name": "crash"]],
            "类别": ["rich_text": [["text": ["content": "crash"]]]],
            "消息": ["rich_text": [["text": ["content": String(message.prefix(2000))]]]],
            "状态": ["select": ["name": "未处理"]],
            "source_file": ["rich_text": [["text": ["content": "signal-handler"]]]]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: properties) else { return false }
        do {
            _ = try await NotionService.shared.createPage(
                databaseId: Self.notionErrorDBId,
                propertiesData: data
            )
            return true
        } catch {
            return false
        }
    }

    private static func signalName(_ sig: Int) -> String {
        switch Int32(sig) {
        case SIGTRAP: return "SIGTRAP"
        case SIGABRT: return "SIGABRT"
        case SIGSEGV: return "SIGSEGV"
        case SIGBUS:  return "SIGBUS"
        case SIGILL:  return "SIGILL"
        case SIGFPE:  return "SIGFPE"
        default: return "UNKNOWN"
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
