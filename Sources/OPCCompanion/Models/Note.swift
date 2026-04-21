import Foundation

public struct Note: Identifiable, Codable, Sendable {
    public let id: UUID
    public var content: String
    public var capturedAt: Date
    public var source: Source
    public var inputMode: InputMode
    public var status: Status
    public var kind: Kind
    public var processedAt: Date?
    public var notionPageId: String?

    public init(
        id: UUID = UUID(),
        content: String,
        capturedAt: Date = Date(),
        source: Source,
        inputMode: InputMode = .text,
        status: Status = .pending,
        kind: Kind = .note,
        processedAt: Date? = nil,
        notionPageId: String? = nil
    ) {
        self.id = id
        self.content = content
        self.capturedAt = capturedAt
        self.source = source
        self.inputMode = inputMode
        self.status = status
        self.kind = kind
        self.processedAt = processedAt
        self.notionPageId = notionPageId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.content = try c.decode(String.self, forKey: .content)
        self.capturedAt = try c.decode(Date.self, forKey: .capturedAt)
        self.source = try c.decode(Source.self, forKey: .source)
        self.inputMode = try c.decode(InputMode.self, forKey: .inputMode)
        self.status = try c.decode(Status.self, forKey: .status)
        self.kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .note
        self.processedAt = try c.decodeIfPresent(Date.self, forKey: .processedAt)
        self.notionPageId = try c.decodeIfPresent(String.self, forKey: .notionPageId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, content, capturedAt, source, inputMode, status, kind, processedAt, notionPageId
    }

    public enum Source: String, Codable, Sendable {
        case hotkeyVoice = "hotkey_voice"
        case hotkeyText = "hotkey_text"
        case slashInPanel = "slash_in_panel"
        case convertFromMessage = "convert_from_message"
    }

    public enum Status: String, Codable, Sendable {
        case pending
        case done
        case deleted
        case expired    // 超过 48h 未处理自动进入这个状态（砍-A）
    }

    public enum Kind: String, Codable, Sendable {
        case note   // 普通随手记（备忘 / 碎片 / 信息）
        case wish   // "我想"：想做但还没做的念头，远期愿望池
    }
}
