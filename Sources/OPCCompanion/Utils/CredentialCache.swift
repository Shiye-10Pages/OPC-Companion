import Foundation

/// 凭证存储：明文 JSON 文件 + 内存缓存。
///
/// 路径默认 `~/.opc-companion/secrets.json`，文件权限 0o600（仅 owner 可读写）。
/// 选择明文文件而非 Keychain 是因为：本地个人工具、单用户、`.gitignore` 已挡 `~/.opc-companion/`，
/// 而 Keychain 在 ad-hoc 签名下每次重打包会反复弹授权。
public final class CredentialCache: @unchecked Sendable {
    public static let shared = CredentialCache()

    private let lock = NSLock()
    private let fileURL: URL
    private var minimaxAPIKey: String = ""
    private var notionToken: String = ""
    private var loaded = false

    public init(fileURL: URL = CredentialCache.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".opc-companion/secrets.json")
    }

    /// 加载凭证。主线程只读 secrets.json（不碰 Keychain，避免 ad-hoc 签名触发系统授权弹窗阻塞启动）。
    /// 旧版 Keychain 中的值在后台异步迁移，失败不影响 app 启动；用户之前从未填写则直接空值进 onboarding。
    public func loadIfNeeded() {
        lock.lock()
        let alreadyLoaded = loaded
        if !alreadyLoaded, let dict = readFromDisk() {
            minimaxAPIKey = dict["minimax_api_key"] ?? ""
            notionToken = dict["notion_token"] ?? ""
            loaded = true
        } else if !alreadyLoaded {
            // 文件不存在 → 创建空文件先让 loaded=true，后台再尝试从 Keychain 补
            loaded = true
            lock.unlock()
            writeToDisk()
            migrateFromKeychainInBackground()
            return
        }
        lock.unlock()
    }

    private func migrateFromKeychainInBackground() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            let kcKey = KeychainHelper.load(account: KeychainHelper.Account.minimaxAPIKey) ?? ""
            let kcTok = KeychainHelper.load(account: KeychainHelper.Account.notionToken) ?? ""
            guard !kcKey.isEmpty || !kcTok.isEmpty else { return }

            self.lock.lock()
            if self.minimaxAPIKey.isEmpty { self.minimaxAPIKey = kcKey }
            if self.notionToken.isEmpty { self.notionToken = kcTok }
            self.lock.unlock()
            self.writeToDisk()
            KeychainHelper.delete(account: KeychainHelper.Account.minimaxAPIKey)
            KeychainHelper.delete(account: KeychainHelper.Account.notionToken)
        }
    }

    public func getMinimaxAPIKey() -> String {
        lock.lock(); defer { lock.unlock() }
        return minimaxAPIKey
    }

    public func setMinimaxAPIKey(_ value: String) {
        lock.lock()
        minimaxAPIKey = value
        lock.unlock()
        writeToDisk()
    }

    public func getNotionToken() -> String {
        lock.lock(); defer { lock.unlock() }
        return notionToken
    }

    public func setNotionToken(_ value: String) {
        lock.lock()
        notionToken = value
        lock.unlock()
        writeToDisk()
    }

    public func resetForTesting() {
        lock.lock(); defer { lock.unlock() }
        minimaxAPIKey = ""
        notionToken = ""
        loaded = false
    }

    // MARK: - I/O

    private func readFromDisk() -> [String: String]? {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        return dict
    }

    private func writeToDisk() {
        lock.lock()
        let snapshot: [String: String] = [
            "minimax_api_key": minimaxAPIKey,
            "notion_token": notionToken
        ]
        lock.unlock()

        let dir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: snapshot,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }

        try? data.write(to: fileURL, options: [.atomic])
        // 文件权限 600：仅 owner 可读写
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
