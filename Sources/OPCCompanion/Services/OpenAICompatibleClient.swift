import Foundation

public final class OpenAICompatibleClient: @unchecked Sendable {
    public static let defaultEndpoint = URL(string: "https://api.minimax.io/v1/text/chatcompletion_v2")!
    public static let defaultModel = "MiniMax-M2.7"

    public struct Config: Sendable {
        public var apiKey: String
        public var endpoint: URL
        public var model: String
        public var maxTokens: Int
        public var temperature: Double?
        public var tokenLimitField: String

        public init(
            apiKey: String,
            endpoint: URL = OpenAICompatibleClient.defaultEndpoint,
            model: String = OpenAICompatibleClient.defaultModel,
            maxTokens: Int = 2048,
            temperature: Double? = 0.7,
            tokenLimitField: String = "max_tokens"
        ) {
            self.apiKey = apiKey
            self.endpoint = endpoint
            self.model = model
            self.maxTokens = maxTokens
            self.temperature = temperature
            self.tokenLimitField = tokenLimitField
        }
    }

    public enum ClientError: Error, LocalizedError {
        case network(underlying: Error)
        case unauthorized          // 401
        case rateLimited           // 429
        case invalidRequest(String) // 400
        case server(status: Int, message: String)  // 5xx
        case httpError(Int, String)  // 其他 HTTP
        case invalidResponse
        case encodingFailed
        case emptyResponse

        public var errorDescription: String? {
            switch self {
            case .network: return "网络连接失败，请检查你的网络"
            case .unauthorized: return "API Key 无效，请到设置页重新填写"
            case .rateLimited: return "请求过于频繁（限流），请稍后再试"
            case .invalidRequest(let msg): return "请求参数错误：\(msg)"
            case .server(_, let msg): return "AI 服务暂时不可用：\(msg)"
            case .httpError(let code, let body): return "HTTP \(code)：\(body)"
            case .invalidResponse: return "AI 服务响应格式异常"
            case .encodingFailed: return "请求体编码失败"
            case .emptyResponse: return "AI 服务没有返回任何内容"
            }
        }

        public var isRetriable: Bool {
            switch self {
            case .network, .server, .rateLimited: return true
            default: return false
            }
        }

        static func categorize(httpStatus: Int, body: String) -> ClientError {
            switch httpStatus {
            case 401, 403: return .unauthorized
            case 400, 422: return .invalidRequest(body.isEmpty ? "参数无效" : body)
            case 429: return .rateLimited
            case 500...599: return .server(status: httpStatus, message: body)
            default: return .httpError(httpStatus, body)
            }
        }
    }

    private let config: Config
    private let session: URLSession

    public init(config: Config, session: URLSession? = nil) {
        self.config = config
        if let session = session {
            self.session = session
        } else {
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.timeoutIntervalForRequest = 30
            sessionConfig.timeoutIntervalForResource = 120
            self.session = URLSession(configuration: sessionConfig)
        }
    }

    /// 发起流式 chat completion；返回 chunk 流。调用方自行累加 content / tool_calls。
    public func chatStream(
        messages: [WireMessage],
        tools: [[String: Any]]
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        let session = self.session
        let endpoint = self.config.endpoint
        let apiKey = self.config.apiKey

        // 在 Task 外先做请求体序列化，避开非 Sendable 的 tools/messages 捕获
        let preparedRequest: URLRequest
        do {
            preparedRequest = try Self.buildRequest(
                config: self.config,
                messages: messages,
                tools: tools,
                stream: true
            )
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
        _ = (endpoint, apiKey)  // 保留以便未来调试，不参与 closure capture

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: preparedRequest)

                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var bodyText = ""
                        for try await line in bytes.lines { bodyText += line + "\n" }
                        continuation.finish(throwing: ClientError.categorize(
                            httpStatus: http.statusCode,
                            body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                        ))
                        return
                    }

                    for try await line in bytes.lines {
                        if Self.isDoneMarker(line) { break }
                        guard let chunk = try Self.parseSSELine(line) else { continue }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch let error as URLError {
                    continuation.finish(throwing: ClientError.network(underlying: error))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable [task] _ in
                task.cancel()
            }
        }
    }

    // MARK: - Request

    private static func buildRequest(config: Config, messages: [WireMessage], tools: [[String: Any]], stream: Bool) throws -> URLRequest {
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let messagesJSON: [[String: Any]] = messages.map { Self.wireMessageToJSON($0) }

        var body: [String: Any] = [
            "model": config.model,
            "messages": messagesJSON,
            "stream": stream,
            config.tokenLimitField: config.maxTokens
        ]
        if let temperature = config.temperature {
            body["temperature"] = temperature
        }
        if !tools.isEmpty {
            body["tools"] = tools
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    private static func wireMessageToJSON(_ m: WireMessage) -> [String: Any] {
        var json: [String: Any] = ["role": m.role]
        if let content = m.content { json["content"] = content }
        if let toolCalls = m.toolCalls, !toolCalls.isEmpty {
            json["tool_calls"] = toolCalls.map { call -> [String: Any] in
                [
                    "id": call.id,
                    "type": call.type,
                    "function": [
                        "name": call.function.name,
                        "arguments": call.function.arguments
                    ]
                ]
            }
        }
        if let toolCallId = m.toolCallId {
            json["tool_call_id"] = toolCallId
        }
        return json
    }

    // MARK: - SSE 解析

    static func isDoneMarker(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed == "data: [DONE]" || trimmed == "data:[DONE]"
    }

    /// 解析一行 SSE（`data: {...}`）。空行/非 data 行/结束标记 返回 nil。
    static func parseSSELine(_ line: String) throws -> StreamChunk? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.hasPrefix("data:") else { return nil }
        if isDoneMarker(trimmed) { return nil }

        let jsonPart = trimmed
            .dropFirst("data:".count)
            .trimmingCharacters(in: .whitespaces)
        guard let data = jsonPart.data(using: .utf8) else { return nil }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let firstChoice = choices.first else {
            return nil
        }

        let delta = firstChoice["delta"] as? [String: Any] ?? [:]
        let contentDelta = delta["content"] as? String
        let finishReason = firstChoice["finish_reason"] as? String

        var toolCallDeltas: [ToolCallDelta] = []
        if let toolCallsRaw = delta["tool_calls"] as? [[String: Any]] {
            for entry in toolCallsRaw {
                let index = entry["index"] as? Int ?? 0
                let id = entry["id"] as? String
                let function = entry["function"] as? [String: Any]
                let name = function?["name"] as? String
                let argFragment = function?["arguments"] as? String
                toolCallDeltas.append(ToolCallDelta(
                    index: index,
                    id: id,
                    name: name,
                    argumentsFragment: argFragment
                ))
            }
        }

        if contentDelta == nil && toolCallDeltas.isEmpty && finishReason == nil {
            return nil
        }

        return StreamChunk(
            contentDelta: contentDelta,
            toolCallDeltas: toolCallDeltas,
            finishReason: finishReason
        )
    }
}
