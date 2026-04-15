import Foundation

public struct AppConfig: Codable {
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

public struct APIConfig: Codable {
    public var provider: String
    public var apiKey: String
    public var baseURL: String

    public init(
        provider: String = "minimax",
        apiKey: String = "",
        baseURL: String = "https://api.minimax.chat/v1"  // MiniMax 海外版
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.baseURL = baseURL
    }
}

public struct ProxyConfig: Codable {
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

public struct NotionDatabaseIds: Codable {
    public var calendar: String?
    public var todos: String?

    public init(calendar: String? = nil, todos: String? = nil) {
        self.calendar = calendar
        self.todos = todos
    }
}

public struct VoiceConfig: Codable {
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