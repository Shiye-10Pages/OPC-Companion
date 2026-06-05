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
        case unauthorized          // 401 / MiniMax 1004,2049
        case rateLimited           // 429 / MiniMax 1002,1039
        case insufficientBalance   // MiniMax 1008（余额/额度不足）
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
            case .insufficientBalance: return "API 余额/额度不足，请到服务商控制台充值后再试"
            case .invalidRequest(let msg): return "请求参数错误：\(msg)"
            case .server(_, let msg): return "AI 服务暂时不可用：\(msg)"
            case .httpError(let code, let body): return "HTTP \(code)：\(body)"
            case .invalidResponse: return "AI 服务响应格式异常"
            case .encodingFailed: return "请求体编码失败"
            case .emptyResponse: return "AI 服务没有返回任何内容"
            }
        }

        /// 紧凑诊断标签，仅用于日志（无隐私）。
        var diagTag: String {
            switch self {
            case .network: return "network"
            case .unauthorized: return "unauthorized"
            case .rateLimited: return "rateLimited"
            case .insufficientBalance: return "insufficientBalance"
            case .invalidRequest: return "invalidRequest"
            case .server(let status, _): return "server(\(status))"
            case .httpError(let code, _): return "http(\(code))"
            case .invalidResponse: return "invalidResponse"
            case .encodingFailed: return "encodingFailed"
            case .emptyResponse: return "emptyResponse"
            }
        }

        public var isRetriable: Bool {
            switch self {
            case .network, .server, .rateLimited: return true
            default: return false
            }
        }

        static func categorize(httpStatus: Int, body: String) -> ClientError {
            let lower = body.lowercased()
            switch httpStatus {
            case 401, 403: return .unauthorized
            case 400, 422: return .invalidRequest(body.isEmpty ? "参数无效" : body)
            case 429: return .rateLimited
            case 500...599:
                // 有些网关把鉴权/余额错也塞进 5xx body（MiniMax 余额不足曾以 500 返回），关键词兜底
                if lower.contains("api key") || lower.contains("invalid_api_key") || lower.contains("unauthorized") {
                    return .unauthorized
                }
                if lower.contains("insufficient") || lower.contains("balance") || lower.contains("余额") {
                    return .insufficientBalance
                }
                return .server(status: httpStatus, message: body)
            default: return .httpError(httpStatus, body)
            }
        }

        /// MiniMax 业务错误信封 `base_resp` 的分类：官方码表优先，码表未覆盖时按 status_msg 关键词兜底，
        /// 避免真鉴权/余额错被笼统当成 .server（"服务暂时不可用"）误导用户。
        static func fromMiniMaxBaseResp(code: Int, message: String) -> ClientError {
            let lower = message.lowercased()
            switch code {
            case 1004, 2049: return .unauthorized        // 鉴权失败 / invalid api key
            case 1008: return .insufficientBalance        // 余额不足
            case 1002, 1039: return .rateLimited          // RPM 限流 / token 限流
            default: break
            }
            if lower.contains("api key") || lower.contains("apikey") || lower.contains("鉴权")
                || lower.contains("not authorized") || lower.contains("unauthorized") {
                return .unauthorized
            }
            if lower.contains("余额") || lower.contains("balance") || lower.contains("欠费") || lower.contains("credit") {
                return .insufficientBalance
            }
            if lower.contains("限流") || lower.contains("rate limit") || lower.contains("too many") {
                return .rateLimited
            }
            return .server(status: code, message: message)
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
        _ = apiKey  // endpoint 现已用于失败日志的 host 标注；apiKey 暂保留待用

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: preparedRequest)

                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var bodyText = ""
                        for try await line in bytes.lines { bodyText += line + "\n" }
                        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let err = ClientError.categorize(httpStatus: http.statusCode, body: trimmed)
                        logError("llm", "http \(http.statusCode) host=\(endpoint.host ?? "?") body=\(LogRedactor.redact(String(trimmed.prefix(200)))) -> \(err.diagTag)")
                        continuation.finish(throwing: err)
                        return
                    }

                    for try await line in bytes.lines {
                        if Self.isDoneMarker(line) { break }
                        guard let chunk = try Self.parseSSELine(line) else { continue }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch let error as URLError {
                    logError("llm", "network host=\(endpoint.host ?? "?") urlerror=\(error.code.rawValue)")
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
        if isDoneMarker(trimmed) { return nil }

        // 取 JSON：标准 SSE 是 "data: {...}"；部分服务端的错误信封是不带 data: 前缀的裸 JSON
        let jsonPart: String
        if trimmed.hasPrefix("data:") {
            jsonPart = String(trimmed.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
        } else if trimmed.hasPrefix("{") {
            jsonPart = trimmed
        } else {
            return nil
        }
        guard let data = jsonPart.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        // 识别流内错误信封：否则会被当"无 choices"静默丢弃，最终伪装成空响应误导用户
        // 形如 {"type":"error","error":{"type":"overloaded_error","http_code":"529"}}
        if (object["type"] as? String) == "error" {
            let err = object["error"] as? [String: Any]
            let etype = (err?["type"] as? String) ?? "error"
            let code = Int((err?["http_code"] as? String) ?? "") ?? 529
            throw ClientError.server(status: code, message: etype == "overloaded_error" ? "服务端过载，请稍后重试" : etype)
        }
        // 形如 {"base_resp":{"status_code":2049,"status_msg":"invalid api key"}}（MiniMax 业务错误，常以 HTTP 200 返回）
        if let base = object["base_resp"] as? [String: Any],
           let code = base["status_code"] as? Int, code != 0 {
            let msg = (base["status_msg"] as? String) ?? "未知错误"
            let err = ClientError.fromMiniMaxBaseResp(code: code, message: msg)
            logError("llm", "minimax base_resp code=\(code) msg=\(LogRedactor.redact(msg)) -> \(err.diagTag)")
            throw err
        }

        let choices = object["choices"] as? [[String: Any]] ?? []
        let firstChoice = choices.first

        let delta = firstChoice?["delta"] as? [String: Any] ?? [:]
        let contentDelta = delta["content"] as? String
        // 推理模型（MiniMax M2 等）把思考放在 reasoning_content、正文在 content；漏接会导致正文为空时整条空响应
        let reasoningDelta = delta["reasoning_content"] as? String
        let finishReason = firstChoice?["finish_reason"] as? String

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

        if contentDelta == nil && reasoningDelta == nil && toolCallDeltas.isEmpty && finishReason == nil {
            return nil
        }

        return StreamChunk(
            contentDelta: contentDelta,
            reasoningDelta: reasoningDelta,
            toolCallDeltas: toolCallDeltas,
            finishReason: finishReason
        )
    }
}
