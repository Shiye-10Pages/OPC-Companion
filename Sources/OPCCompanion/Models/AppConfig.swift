import Foundation

public struct AppConfig: Codable, Sendable {
    public var hotkey: String
    public var systemPromptFile: String
    public var notionDatabaseIds: NotionDatabaseIds
    public var voice: VoiceConfig
    public var apiConfig: APIConfig
    public var proxyConfig: ProxyConfig

    public init(
        hotkey: String = "option+space",
        systemPromptFile: String = "~/.opc-companion/system-prompt.txt",
        notionDatabaseIds: NotionDatabaseIds = NotionDatabaseIds(),
        voice: VoiceConfig = VoiceConfig(),
        apiConfig: APIConfig = APIConfig(),
        proxyConfig: ProxyConfig = ProxyConfig()
    ) {
        self.hotkey = hotkey
        self.systemPromptFile = systemPromptFile
        self.notionDatabaseIds = notionDatabaseIds
        self.voice = voice
        self.apiConfig = apiConfig
        self.proxyConfig = proxyConfig
    }
}

public struct APIConfig: Codable, Sendable {
    public static let miniMaxInternationalBaseURL = "https://api.minimax.io/v1"
    public static let legacyMiniMaxBaseURL = "https://api.minimax.chat/v1"
    public static let miniMaxDefaultModel = "MiniMax-M2.7"

    public var provider: String
    public var apiKey: String
    public var baseURL: String

    public init(
        provider: String = "minimax",
        apiKey: String = "",
        baseURL: String = APIConfig.miniMaxInternationalBaseURL
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    public var normalizedBaseURL: String {
        if provider == "minimax" && baseURL == Self.legacyMiniMaxBaseURL {
            return Self.miniMaxInternationalBaseURL
        }
        return baseURL
    }

    public var defaultModel: String {
        switch provider {
        case "minimax":
            return Self.miniMaxDefaultModel
        default:
            return Self.miniMaxDefaultModel
        }
    }
}

public struct ProxyConfig: Codable, Sendable {
    public var enabled: Bool
    public var host: String
    public var port: Int

    public init(
        enabled: Bool = false,
        host: String = "127.0.0.1",
        port: Int = 7890
    ) {
        self.enabled = enabled
        self.host = host
        self.port = port
    }
}

public struct NotionDatabaseIds: Codable, Sendable {
    public var calendar: String?
    public var todos: String?
    public var inbox: String?

    public init(calendar: String? = nil, todos: String? = nil, inbox: String? = nil) {
        self.calendar = calendar
        self.todos = todos
        self.inbox = inbox
    }

    public func id(for key: String) -> String? {
        switch key {
        case "calendar": return calendar
        case "todos": return todos
        case "inbox": return inbox
        default: return nil
        }
    }
}

public struct VoiceConfig: Codable, Sendable {
    public var ttsVoice: String
    public var ttsRate: Double

    public init(
        ttsVoice: String = "com.apple.voice.compact.zh-CN.Tingting",
        ttsRate: Double = 0.5
    ) {
        self.ttsVoice = ttsVoice
        self.ttsRate = ttsRate
    }
}
