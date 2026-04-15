import Foundation

public final class ChatEngine: @unchecked Sendable {
    public static let shared = ChatEngine()

    private let claudePath = "/Users/shiye/.local/bin/claude"

    // 代理配置
    private let httpProxy = ProcessInfo.processInfo.environment["http_proxy"]
        ?? ProcessInfo.processInfo.environment["HTTP_PROXY"]
    private let httpsProxy = ProcessInfo.processInfo.environment["https_proxy"]
        ?? ProcessInfo.processInfo.environment["HTTPS_PROXY"]
    private let allProxy = ProcessInfo.processInfo.environment["all_proxy"]
        ?? ProcessInfo.processInfo.environment["ALL_PROXY"]

    public init() {}

    private func setupProxyEnvironment(for process: Process) {
        var env = ProcessInfo.processInfo.environment
        // 移除硬编码的 BASE_URL，让 Claude CLI 直接连接
        env.removeValue(forKey: "ANTHROPIC_BASE_URL")
        // 只使用系统现有的代理设置
        if let proxy = httpProxy ?? httpsProxy ?? allProxy {
            env["http_proxy"] = proxy
            env["HTTP_PROXY"] = proxy
            env["https_proxy"] = proxy
            env["HTTPS_PROXY"] = proxy
            env["ALL_PROXY"] = proxy
            env["all_proxy"] = proxy
        }
        process.environment = env
    }

    public func sendMessage(_ userMessage: String, systemPrompt: String) async throws -> String {
        let sessionId = UUID().uuidString  // session-id 必须是 UUID 格式

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = [
            "-p",
            "--system-prompt", systemPrompt,
            "--session-id", sessionId,
            "--output-format", "json",
            userMessage
        ]

        // 设置代理环境
        setupProxyEnvironment(for: process)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw ChatError.invalidResponse
        }

        // 解析 JSON 输出
        if let json = try? JSONDecoder().decode(ClaudeResponse.self, from: output.data(using: .utf8)!) {
            return json.result.content.first?.text ?? output
        }

        // 如果不是 JSON，直接返回原始输出
        return output
    }

    public func sendMessageWithMCP(_ userMessage: String, systemPrompt: String, mcpConfigPath: String?) async throws -> String {
        let sessionId = UUID().uuidString  // session-id 必须是 UUID 格式

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)

        var arguments = [
            "-p",
            "--system-prompt", systemPrompt,
            "--session-id", sessionId,
            "--output-format", "json"
        ]

        if let mcpPath = mcpConfigPath {
            arguments.append(contentsOf: ["--mcp-config", mcpPath])
        }

        arguments.append(userMessage)
        process.arguments = arguments

        // 设置代理环境
        setupProxyEnvironment(for: process)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw ChatError.invalidResponse
        }

        if let json = try? JSONDecoder().decode(ClaudeResponse.self, from: output.data(using: .utf8)!) {
            return json.result.content.first?.text ?? output
        }

        return output
    }

    public func parseActions(from response: String) -> [Action] {
        var actions: [Action] = []

        // 解析 timer action (开始计时)
        if let timerMatch = response.range(of: #"\[ACTION:timer:start:\{[^}]+\}\]"#, options: .regularExpression) {
            let actionString = String(response[timerMatch])
            if let data = actionString
                .replacingOccurrences(of: "[ACTION:timer:start:", with: "")
                .replacingOccurrences(of: "]", with: "")
                .data(using: .utf8),
               let timerAction = try? JSONDecoder().decode(TimerAction.self, from: data) {
                actions.append(.timer(timerAction))
            }
        }

        // 解析 timer extend action (延长计时)
        if let extendMatch = response.range(of: #"\[ACTION:timer:extend:\{[^}]+\}\]"#, options: .regularExpression) {
            let actionString = String(response[extendMatch])
            if let data = actionString
                .replacingOccurrences(of: "[ACTION:timer:extend:", with: "")
                .replacingOccurrences(of: "]", with: "")
                .data(using: .utf8),
               let extendAction = try? JSONDecoder().decode(TimerExtendAction.self, from: data) {
                actions.append(.timerExtend(extendAction))
            }
        }

        // 解析 notion action
        if let notionMatch = response.range(of: #"\[ACTION:notion:[^\]]+\]"#, options: .regularExpression) {
            let actionString = String(response[notionMatch])
            if let data = actionString
                .replacingOccurrences(of: "[ACTION:notion:", with: "")
                .replacingOccurrences(of: "]", with: "")
                .data(using: .utf8),
               let notionAction = try? JSONDecoder().decode(NotionAction.self, from: data) {
                actions.append(.notion(notionAction))
            }
        }

        return actions
    }

    public enum ChatError: Error, LocalizedError {
        case invalidResponse
        case claudeNotFound

        public var errorDescription: String? {
            switch self {
            case .invalidResponse: return "无法获取有效响应"
            case .claudeNotFound: return "未找到 Claude CLI"
            }
        }
    }
}

struct ClaudeResponse: Codable {
    let result: ClaudeResult
}

struct ClaudeResult: Codable {
    let content: [ClaudeContent]
}

struct ClaudeContent: Codable {
    let text: String
    let type: String?
}

public enum Action {
    case timer(TimerAction)
    case timerExtend(TimerExtendAction)
    case notion(NotionAction)
}

public struct TimerAction: Codable {
    public let task: String
    public let minutes: Int

    public init(task: String, minutes: Int) {
        self.task = task
        self.minutes = minutes
    }
}

public struct TimerExtendAction: Codable {
    public let task: String
    public let minutes: Int

    public init(task: String, minutes: Int) {
        self.task = task
        self.minutes = minutes
    }
}

public struct NotionAction: Codable {
    public let operation: String
    public let parameters: [String: String]

    public init(operation: String, parameters: [String: String]) {
        self.operation = operation
        self.parameters = parameters
    }
}