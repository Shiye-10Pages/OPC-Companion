import Foundation

public struct Message: Identifiable, Codable {
    public let id: UUID
    public var role: MessageRole
    public var content: String
    public var timestamp: Date
    public var inputMode: InputMode
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        inputMode: InputMode = .text,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.inputMode = inputMode
        self.metadata = metadata
    }
}

public enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

public enum InputMode: String, Codable {
    case text
    case voice
}