import Foundation

public struct AppConfig: Codable, Sendable {
    public var hotkey: String
    public var systemPromptFile: String
    public var notionDatabaseIds: NotionDatabaseIds
    public var voice: VoiceConfig
    public var apiConfig: APIConfig
    public var proxyConfig: ProxyConfig
    public var themeID: String
    /// 颜色方案：system / light / dark
    public var colorSchemeOverride: String
    /// 字体方案 ID（FontStyleID 字符串）
    public var fontStyleID: String
    /// 入口模式：quietField（Quiet Field 前门）/ classic（旧三胶囊面板）
    public var entryMode: String

    public init(
        hotkey: String = "option+space",
        systemPromptFile: String = "~/.opc-companion/system-prompt.txt",
        notionDatabaseIds: NotionDatabaseIds = NotionDatabaseIds(),
        voice: VoiceConfig = VoiceConfig(),
        apiConfig: APIConfig = APIConfig(),
        proxyConfig: ProxyConfig = ProxyConfig(),
        themeID: String = "aurora",
        colorSchemeOverride: String = "system",
        fontStyleID: String = "readable",
        entryMode: String = "quietField"
    ) {
        self.hotkey = hotkey
        self.systemPromptFile = systemPromptFile
        self.notionDatabaseIds = notionDatabaseIds
        self.voice = voice
        self.apiConfig = apiConfig
        self.proxyConfig = proxyConfig
        self.themeID = themeID
        self.colorSchemeOverride = colorSchemeOverride
        self.fontStyleID = fontStyleID
        self.entryMode = entryMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey) ?? "option+space"
        self.systemPromptFile = try c.decodeIfPresent(String.self, forKey: .systemPromptFile)
            ?? "~/.opc-companion/system-prompt.txt"
        self.notionDatabaseIds = try c.decodeIfPresent(NotionDatabaseIds.self, forKey: .notionDatabaseIds)
            ?? NotionDatabaseIds()
        self.voice = try c.decodeIfPresent(VoiceConfig.self, forKey: .voice) ?? VoiceConfig()
        self.apiConfig = try c.decodeIfPresent(APIConfig.self, forKey: .apiConfig) ?? APIConfig()
        self.proxyConfig = try c.decodeIfPresent(ProxyConfig.self, forKey: .proxyConfig) ?? ProxyConfig()
        self.themeID = try c.decodeIfPresent(String.self, forKey: .themeID) ?? "aurora"
        self.colorSchemeOverride = try c.decodeIfPresent(String.self, forKey: .colorSchemeOverride) ?? "system"
        self.fontStyleID = try c.decodeIfPresent(String.self, forKey: .fontStyleID) ?? "readable"
        self.entryMode = try c.decodeIfPresent(String.self, forKey: .entryMode) ?? "quietField"
    }

    enum CodingKeys: String, CodingKey {
        case hotkey, systemPromptFile, notionDatabaseIds, voice, apiConfig, proxyConfig, themeID
        case colorSchemeOverride, fontStyleID, entryMode
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
