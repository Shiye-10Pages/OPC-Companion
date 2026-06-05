import Foundation

/// Notion API v1 直连客户端。
public final class NotionService: @unchecked Sendable {
    public static let shared = NotionService()

    public static let baseURL = URL(string: "https://api.notion.com/v1")!
    public static let apiVersion = "2022-06-28"

    private let session: URLSession
    private let schemaLock = NSLock()
    private var schemaCache: [String: NotionDatabaseSchema] = [:]

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - 凭证

    /// 读内存缓存中的 Notion Token（启动时已从 Keychain 加载）；空则抛错。
    public static func resolvedToken() throws -> String {
        let token = CredentialCache.shared.getNotionToken().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw NotionError.missingToken }
        return token
    }

    // MARK: - 端点

    /// 搜索用户可访问的所有数据库。
    public func searchDatabases() async throws -> [NotionDatabase] {
        let body: [String: Any] = ["filter": ["value": "database", "property": "object"]]
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
        let request = try makeRequest(path: "/search", method: "POST", bodyData: bodyData)
        let (data, response) = try await session.data(for: request)
        try Self.ensureSuccess(data: data, response: response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            throw NotionError.invalidResponse
        }

        return results.compactMap { obj -> NotionDatabase? in
            guard let id = obj["id"] as? String else { return nil }
            let title = Self.extractPlainTextTitle(from: obj["title"] as? [[String: Any]])
            return NotionDatabase(id: id, title: title)
        }
    }

    /// 查询数据库。bodyData 是已序列化的 JSON Data；为空则发空 body。
    public func queryDatabase(databaseId: String, bodyData: Data) async throws -> Data {
        let request = try makeRequest(
            path: "/databases/\(databaseId)/query",
            method: "POST",
            bodyData: bodyData
        )
        let (data, response) = try await session.data(for: request)
        try Self.ensureSuccess(data: data, response: response)
        return data
    }

    /// 新建页面。propertiesData 是 properties 字段的 JSON Data。
    @discardableResult
    public func createPage(databaseId: String, propertiesData: Data) async throws -> Data {
        var bodyDict: [String: Any] = ["parent": ["database_id": databaseId]]
        if let props = try JSONSerialization.jsonObject(with: propertiesData) as? [String: Any] {
            bodyDict["properties"] = props
        }
        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict, options: [])
        let request = try makeRequest(path: "/pages", method: "POST", bodyData: bodyData)
        let (data, response) = try await session.data(for: request)
        try Self.ensureSuccess(data: data, response: response)
        return data
    }

    /// 更新页面属性。
    @discardableResult
    public func updatePage(pageId: String, propertiesData: Data) async throws -> Data {
        var bodyDict: [String: Any] = [:]
        if let props = try JSONSerialization.jsonObject(with: propertiesData) as? [String: Any] {
            bodyDict["properties"] = props
        }
        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict, options: [])
        let request = try makeRequest(
            path: "/pages/\(pageId)",
            method: "PATCH",
            bodyData: bodyData
        )
        let (data, response) = try await session.data(for: request)
        try Self.ensureSuccess(data: data, response: response)
        return data
    }

    // MARK: - 数据库 Schema（用于写入前校正列名）

    /// 拉取数据库字段 schema（`GET /databases/{id}`），按 id 缓存。
    public func databaseSchema(databaseId: String, forceRefresh: Bool = false) async throws -> NotionDatabaseSchema {
        if !forceRefresh, let cached = cachedSchema(databaseId) { return cached }
        let request = try makeRequest(path: "/databases/\(databaseId)", method: "GET")
        let (data, response) = try await session.data(for: request)
        try Self.ensureSuccess(data: data, response: response)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NotionError.invalidResponse
        }
        let schema = try Self.parseSchema(json)
        storeSchema(schema, for: databaseId)
        return schema
    }

    // 同步小封装：async 上下文不能直接持 NSLock，临界区里也无 await
    private func cachedSchema(_ id: String) -> NotionDatabaseSchema? {
        schemaLock.lock(); defer { schemaLock.unlock() }
        return schemaCache[id]
    }

    private func storeSchema(_ schema: NotionDatabaseSchema, for id: String) {
        schemaLock.lock(); defer { schemaLock.unlock() }
        schemaCache[id] = schema
    }

    /// 便捷：返回真实标题列名；失败时回退 "Name"（英文库默认标题列名）。
    public func titlePropertyName(databaseId: String) async -> String {
        (try? await databaseSchema(databaseId: databaseId))?.titlePropertyName ?? "Name"
    }

    /// 从 `GET /databases/{id}` 的 JSON 里解析出标题列名与全部列名。提取成静态便于单测。
    static func parseSchema(_ json: [String: Any]) throws -> NotionDatabaseSchema {
        guard let props = json["properties"] as? [String: Any] else {
            throw NotionError.invalidResponse
        }
        var titleName: String?
        var names: Set<String> = []
        for (name, val) in props {
            names.insert(name)
            if let v = val as? [String: Any], (v["type"] as? String) == "title" {
                titleName = name
            }
        }
        guard let title = titleName else { throw NotionError.invalidResponse }
        return NotionDatabaseSchema(titlePropertyName: title, propertyNames: names)
    }

    // MARK: - 构造请求

    static func makeRequest(
        path: String,
        method: String,
        bodyData: Data?,
        token: String,
        baseURL: URL = NotionService.baseURL
    ) throws -> URLRequest {
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        let urlString = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + normalizedPath
        guard let url = URL(string: urlString) else {
            throw NotionError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if method != "GET", let bodyData = bodyData, !bodyData.isEmpty {
            request.httpBody = bodyData
        }
        return request
    }

    private func makeRequest(path: String, method: String, bodyData: Data? = nil) throws -> URLRequest {
        let token = try Self.resolvedToken()
        return try Self.makeRequest(path: path, method: method, bodyData: bodyData, token: token)
    }

    // MARK: - 响应检查

    private static func ensureSuccess(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw NotionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.extractErrorMessage(data: data) ?? "HTTP \(http.statusCode)"
            throw NotionError.categorize(httpStatus: http.statusCode, message: message)
        }
    }

    private static func extractErrorMessage(data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        return json["message"] as? String
    }

    // MARK: - Helpers

    private static func extractPlainTextTitle(from title: [[String: Any]]?) -> String {
        guard let parts = title else { return "" }
        return parts.compactMap { $0["plain_text"] as? String }.joined()
    }
}

public struct NotionDatabase: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// 数据库字段 schema（当前只取写入需要的：真实标题列名 + 全部列名）。
public struct NotionDatabaseSchema: Sendable, Equatable {
    public let titlePropertyName: String
    public let propertyNames: Set<String>

    public init(titlePropertyName: String, propertyNames: Set<String>) {
        self.titlePropertyName = titlePropertyName
        self.propertyNames = propertyNames
    }
}

public enum NotionError: Error, LocalizedError {
    case missingToken
    case invalidURL
    case invalidResponse
    case unauthorized             // 401
    case notFound(String)         // 404（数据库 / 页面不存在）
    case rateLimited              // 429
    case invalidInput(String)     // 400（schema / 字段错）
    case server(status: Int, message: String)  // 5xx
    case httpError(status: Int, message: String)
    case network(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .missingToken: return "请先在设置中填写 Notion Token"
        case .invalidURL: return "Notion URL 构造失败"
        case .invalidResponse: return "Notion 响应格式异常"
        case .unauthorized: return "Notion Token 无效或已过期，请到设置重新填写"
        case .notFound(let msg): return "Notion 资源未找到：\(msg)"
        case .rateLimited: return "Notion 请求过于频繁，请稍后再试"
        case .invalidInput(let msg): return "Notion 参数错误：\(msg)"
        case .server(_, let msg): return "Notion 服务暂时不可用：\(msg)"
        case .httpError(let status, let message): return "Notion HTTP \(status)：\(message)"
        case .network: return "网络连接失败，请检查你的网络"
        }
    }

    static func categorize(httpStatus: Int, message: String) -> NotionError {
        switch httpStatus {
        case 401, 403: return .unauthorized
        case 404: return .notFound(message)
        case 400, 422: return .invalidInput(message)
        case 429: return .rateLimited
        case 500...599: return .server(status: httpStatus, message: message)
        default: return .httpError(status: httpStatus, message: message)
        }
    }
}
