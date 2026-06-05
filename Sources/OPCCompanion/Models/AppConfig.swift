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
    public static let defaultProvider = "minimax"
    public static let miniMaxInternationalBaseURL = "https://api.minimax.io/v1"
    public static let legacyMiniMaxBaseURL = "https://api.minimax.chat/v1"
    public static let miniMaxDefaultModel = "MiniMax-M2.7"
    public static let deepSeekBaseURL = "https://api.deepseek.com"
    public static let deepSeekDefaultModel = "deepseek-v4-flash"
    public static let qwenBaseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    public static let qwenDefaultModel = "qwen-plus"
    public static let openAIBaseURL = "https://api.openai.com/v1"
    public static let openAIDefaultModel = "gpt-5.4-mini"
    public static let anthropicBaseURL = "https://api.anthropic.com/v1"
    public static let anthropicDefaultModel = "claude-sonnet-4-6"
    public static let siliconFlowBaseURL = "https://api.siliconflow.cn/v1"
    public static let siliconFlowDefaultModel = "deepseek-ai/DeepSeek-V3.2"
    // MiniMax 国内版：与海外同模型/同端点路径，但 host 与 key 必须区域匹配，不可混用
    public static let miniMaxCNBaseURL = "https://api.minimaxi.com/v1"
    public static let glmBaseURL = "https://open.bigmodel.cn/api/paas/v4"
    public static let glmDefaultModel = "glm-4.6"
    public static let kimiBaseURL = "https://api.moonshot.cn/v1"
    public static let kimiDefaultModel = "kimi-latest"

    public var provider: String
    public var apiKey: String
    public var baseURL: String
    public var model: String

    public init(
        provider: String = APIConfig.defaultProvider,
        apiKey: String = "",
        baseURL: String = "",
        model: String = ""
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.baseURL = baseURL.isEmpty ? Self.defaultBaseURL(for: provider) : baseURL
        self.model = model
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? Self.defaultProvider
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? Self.defaultBaseURL(for: provider)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case provider, apiKey, baseURL, model
    }

    public var normalizedBaseURL: String {
        if provider == "minimax" && baseURL == Self.legacyMiniMaxBaseURL {
            return Self.miniMaxInternationalBaseURL
        }
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultBaseURL(for: provider) : trimmed
    }

    public var defaultModel: String {
        Self.defaultModel(for: provider)
    }

    public var resolvedModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultModel : trimmed
    }

    public var providerDisplayName: String {
        Self.displayName(for: provider)
    }

    public var completionEndpoint: URL? {
        let base = normalizedBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !base.isEmpty else { return nil }
        if base.hasSuffix("/chat/completions") || base.hasSuffix("/text/chatcompletion_v2") {
            return URL(string: base)
        }
        let path = Self.usesMiniMaxPath(provider) ? "text/chatcompletion_v2" : "chat/completions"
        return URL(string: "\(base)/\(path)")
    }

    /// MiniMax 系（海外 / 国内）用 text/chatcompletion_v2 端点；其余 OpenAI 兼容厂商用 chat/completions。
    static func usesMiniMaxPath(_ provider: String) -> Bool {
        provider == "minimax" || provider == "minimax-cn"
    }

    public static func defaultBaseURL(for provider: String) -> String {
        switch provider {
        case "minimax": return miniMaxInternationalBaseURL
        case "minimax-cn": return miniMaxCNBaseURL
        case "deepseek": return deepSeekBaseURL
        case "qwen": return qwenBaseURL
        case "glm": return glmBaseURL
        case "kimi": return kimiBaseURL
        case "openai": return openAIBaseURL
        case "anthropic": return anthropicBaseURL
        case "siliconflow": return siliconFlowBaseURL
        default: return ""
        }
    }

    public static func defaultModel(for provider: String) -> String {
        switch provider {
        case "minimax": return miniMaxDefaultModel
        case "minimax-cn": return miniMaxDefaultModel
        case "deepseek": return deepSeekDefaultModel
        case "qwen": return qwenDefaultModel
        case "glm": return glmDefaultModel
        case "kimi": return kimiDefaultModel
        case "openai": return openAIDefaultModel
        case "anthropic": return anthropicDefaultModel
        case "siliconflow": return siliconFlowDefaultModel
        default: return ""
        }
    }

    public static func displayName(for provider: String) -> String {
        switch provider {
        case "minimax": return "MiniMax (海外版)"
        case "minimax-cn": return "MiniMax (国内版)"
        case "deepseek": return "DeepSeek"
        case "qwen": return "通义千问"
        case "glm": return "智谱 GLM"
        case "kimi": return "Kimi (Moonshot)"
        case "openai": return "OpenAI"
        case "anthropic": return "Anthropic"
        case "siliconflow": return "SiliconFlow"
        default: return "自定义服务"
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
