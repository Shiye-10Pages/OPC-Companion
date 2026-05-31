import Foundation

public struct Message: Identifiable, Codable, Sendable {
    public let id: UUID
    public var role: MessageRole
    public var content: String
    public var timestamp: Date
    public var inputMode: InputMode
    public var metadata: [String: String]
    public var hidden: Bool

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        inputMode: InputMode = .text,
        metadata: [String: String] = [:],
        hidden: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.inputMode = inputMode
        self.metadata = metadata
        self.hidden = hidden
    }

    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, inputMode, metadata, hidden
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.role = try c.decode(MessageRole.self, forKey: .role)
        self.content = try c.decode(String.self, forKey: .content)
        self.timestamp = try c.decode(Date.self, forKey: .timestamp)
        self.inputMode = try c.decodeIfPresent(InputMode.self, forKey: .inputMode) ?? .text
        self.metadata = try c.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
        self.hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
    }
}

public enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

public enum InputMode: String, Codable, Sendable {
    case text
    case voice
}

// MessageRole.chatCompletionRole 已删除（死代码，wire 格式转换走 WireMessage）
