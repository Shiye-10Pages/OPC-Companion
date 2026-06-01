import Foundation

/// 凭证存储：macOS Keychain（唯一持久化）+ 内存缓存。**绝不明文落盘。**
///
/// 历史明文 `~/.opc-companion/secrets.json` 会在启动时迁移进 Keychain，然后删除明文文件。
/// 之后 API key / Notion token 只存在 Keychain + 进程内存缓存里，磁盘上不留任何明文。
/// 代价：ad-hoc 签名每次重打包后，Keychain 首次访问可能弹一次系统授权——这是安全的必要成本。
public final class CredentialCache: @unchecked Sendable {
    public static let shared = CredentialCache()

    /// 测试环境只走内存，不碰真 Keychain（避免污染开发机钥匙串 / CI 弹窗）。
    private static let isTesting = NSClassFromString("XCTestCase") != nil

    private let lock = NSLock()
    /// 仅用于一次性迁移并删除历史明文文件，不再写入。
    private let fileURL: URL
    private var apiKeys: [String: String] = [:]
    private var notionToken = ""
    private var loadedAPIKeyProviders: Set<String> = []
    private var notionLoaded = false

    public init(fileURL: URL = CredentialCache.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".opc-companion/secrets.json")
    }

    /// 启动调用：把历史明文 secrets.json 迁进 Keychain，再删掉明文文件（绝不再落盘）。
    public func loadIfNeeded() {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return
        }
        let key = dict["minimax_api_key"] ?? ""
        let tok = dict["notion_token"] ?? ""
        var migratedOK = true
        if !key.isEmpty {
            if !Self.isTesting, !KeychainHelper.save(account: KeychainHelper.Account.apiKey(provider: APIConfig.defaultProvider), value: key) { migratedOK = false }
            lock.lock()
            apiKeys[APIConfig.defaultProvider] = key
            loadedAPIKeyProviders.insert(APIConfig.defaultProvider)
            lock.unlock()
        }
        if !tok.isEmpty {
            if !Self.isTesting, !KeychainHelper.save(account: KeychainHelper.Account.notionToken, value: tok) { migratedOK = false }
            lock.lock(); notionToken = tok; notionLoaded = true; lock.unlock()
        }
        // 只有确实写进 Keychain 才删明文文件，避免 Keychain 写失败导致凭证丢失
        if migratedOK {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    public func getAPIKey(provider: String) -> String {
        let normalizedProvider = Self.normalizedProvider(provider)
        lock.lock()
        if loadedAPIKeyProviders.contains(normalizedProvider) {
            let value = apiKeys[normalizedProvider] ?? ""
            lock.unlock()
            return value
        }
        lock.unlock()
        // 不持锁做 Keychain I/O：授权弹窗期间持锁会让其它线程死锁
        let account = KeychainHelper.Account.apiKey(provider: normalizedProvider)
        let fromKeychain = Self.isTesting ? "" : (KeychainHelper.load(account: account) ?? "")
        lock.lock(); defer { lock.unlock() }
        if !loadedAPIKeyProviders.contains(normalizedProvider) {
            apiKeys[normalizedProvider] = fromKeychain
            loadedAPIKeyProviders.insert(normalizedProvider)
        }
        return apiKeys[normalizedProvider] ?? ""
    }

    @discardableResult
    public func setAPIKey(_ value: String, provider: String) -> Bool {
        let normalizedProvider = Self.normalizedProvider(provider)
        let account = KeychainHelper.Account.apiKey(provider: normalizedProvider)
        if !Self.isTesting, !KeychainHelper.save(account: account, value: value) {
            OPCLogger.shared.log(.error, "credential", "\(normalizedProvider) API Key 写入 Keychain 失败")
            return false
        }
        lock.lock()
        apiKeys[normalizedProvider] = value
        loadedAPIKeyProviders.insert(normalizedProvider)
        lock.unlock()
        return true
    }

    public func getMinimaxAPIKey() -> String {
        getAPIKey(provider: APIConfig.defaultProvider)
    }

    @discardableResult
    public func setMinimaxAPIKey(_ value: String) -> Bool {
        setAPIKey(value, provider: APIConfig.defaultProvider)
    }

    public func getNotionToken() -> String {
        lock.lock()
        if notionLoaded { let v = notionToken; lock.unlock(); return v }
        lock.unlock()
        let fromKeychain = Self.isTesting ? "" : (KeychainHelper.load(account: KeychainHelper.Account.notionToken) ?? "")
        lock.lock(); defer { lock.unlock() }
        if !notionLoaded { notionToken = fromKeychain; notionLoaded = true }
        return notionToken
    }

    @discardableResult
    public func setNotionToken(_ value: String) -> Bool {
        if !Self.isTesting, !KeychainHelper.save(account: KeychainHelper.Account.notionToken, value: value) {
            OPCLogger.shared.log(.error, "credential", "Notion Token 写入 Keychain 失败")
            return false
        }
        lock.lock(); notionToken = value; notionLoaded = true; lock.unlock()
        return true
    }

    public func resetForTesting() {
        lock.lock(); defer { lock.unlock() }
        apiKeys = [:]
        notionToken = ""
        loadedAPIKeyProviders = []
        notionLoaded = false
    }

    private static func normalizedProvider(_ provider: String) -> String {
        let value = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty ? APIConfig.defaultProvider : value
    }
}
