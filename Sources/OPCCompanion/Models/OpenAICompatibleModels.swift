import Foundation

/// OpenAI-compatible chat completion 的消息格式
public struct WireMessage: Codable, Sendable {
    public var role: String  // "system" | "user" | "assistant" | "tool"
    public var content: String?
    public var toolCalls: [WireToolCall]?
    public var toolCallId: String?  // 仅 role=tool 用

    public init(role: String, content: String? = nil, toolCalls: [WireToolCall]? = nil, toolCallId: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }
}

public struct WireToolCall: Codable, Sendable {
    public let id: String
    public let type: String   // "function"
    public let function: WireFunctionCall

    public init(id: String, type: String = "function", function: WireFunctionCall) {
        self.id = id
        self.type = type
        self.function = function
    }
}

public struct WireFunctionCall: Codable, Sendable {
    public let name: String
    public let arguments: String  // JSON string
}

/// 一次流式响应 chunk（完整解析完成后）
public struct StreamChunk: Sendable {
    public var contentDelta: String?
    public var reasoningDelta: String?
    public var toolCallDeltas: [ToolCallDelta]
    public var finishReason: String?

    public init(
        contentDelta: String? = nil,
        reasoningDelta: String? = nil,
        toolCallDeltas: [ToolCallDelta] = [],
        finishReason: String? = nil
    ) {
        self.contentDelta = contentDelta
        self.reasoningDelta = reasoningDelta
        self.toolCallDeltas = toolCallDeltas
        self.finishReason = finishReason
    }
}

public struct ToolCallDelta: Sendable {
    public let index: Int
    public let id: String?
    public let name: String?
    public let argumentsFragment: String?
}

/// 增量拼接 tool_calls 的缓冲区；SSE chunk 可能把 id/name/arguments 分多帧发。
public final class ToolCallBuffer: @unchecked Sendable {
    public var slots: [Slot] = []

    public struct Slot: Sendable {
        public var id: String = ""
        public var name: String = ""
        public var arguments: String = ""
    }

    public init() {}

    public func apply(delta: ToolCallDelta) {
        while slots.count <= delta.index {
            slots.append(Slot())
        }
        if let id = delta.id, !id.isEmpty { slots[delta.index].id = id }
        if let name = delta.name, !name.isEmpty { slots[delta.index].name = name }
        if let fragment = delta.argumentsFragment { slots[delta.index].arguments += fragment }
    }

    public func finalized() -> [WireToolCall] {
        slots.compactMap { slot in
            guard !slot.id.isEmpty, !slot.name.isEmpty else { return nil }
            return WireToolCall(
                id: slot.id,
                function: WireFunctionCall(name: slot.name, arguments: slot.arguments)
            )
        }
    }
}
