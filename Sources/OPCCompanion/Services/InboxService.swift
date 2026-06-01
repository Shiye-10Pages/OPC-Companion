import Foundation

public final class InboxService: @unchecked Sendable {
    public static let shared = InboxService(fileURL: InboxService.defaultURL)

    private let lock = NSLock()
    private let fileURL: URL

    public init(fileURL: URL = InboxService.defaultURL) {
        self.fileURL = fileURL
    }

    public func loadAll() -> [Note] {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return text.components(separatedBy: .newlines).compactMap { line -> Note? in
            guard !line.isEmpty, let lineData = line.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(Note.self, from: lineData)
        }
    }

    @discardableResult
    public func append(_ note: Note) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard ensureDirectory() else { return false }

        guard let encoded = try? JSONEncoder().encode(note),
              let line = String(data: encoded, encoding: .utf8),
              let lineData = line.data(using: .utf8),
              let newlineData = "\n".data(using: .utf8) else {
            logError("persist", "InboxService.append 编码失败 id=\(note.id)")
            return false
        }

        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                var payload = newlineData
                payload.append(lineData)
                try handle.write(contentsOf: payload)
            } else {
                try line.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            return true
        } catch {
            logError("persist", "InboxService.append 写入失败 \(fileURL.path): \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    public func saveAll(_ notes: [Note]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard ensureDirectory() else { return false }

        let lines: [String]
        do {
            lines = try notes.map { note in
                let data = try JSONEncoder().encode(note)
                guard let line = String(data: data, encoding: .utf8) else {
                    throw CocoaError(.fileWriteInapplicableStringEncoding)
                }
                return line
            }
        } catch {
            logError("persist", "InboxService.saveAll 编码失败: \(error.localizedDescription)")
            return false
        }
        do {
            try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            logError("persist", "InboxService.saveAll 写入失败 \(fileURL.path): \(error.localizedDescription)")
            return false
        }
    }

    public static var defaultURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".opc-companion/inbox/notes.jsonl")
    }

    /// 砍-A：扫描随手记，把 pending 且 capturedAt 距今 >48h 的标记为 .expired。
    /// state 的 notes 数组同步更新，便于 UI 实时反映。
    /// 注意：kind == .wish 的"我想"条目属于远期愿望池，不参与 48h 过期机制。
    @MainActor
    public func expirePendingNotesOlderThan48h(state: AppState) {
        let cutoff = Date().addingTimeInterval(-48 * 3600)
        let original = state.notes
        var changed = false
        for i in state.notes.indices
            where state.notes[i].status == .pending
                && state.notes[i].kind != .wish
                && state.notes[i].capturedAt < cutoff {
            state.notes[i].status = .expired
            state.notes[i].processedAt = Date()
            changed = true
        }
        if changed, !saveAll(state.notes) {
            state.notes = original
            state.showBanner("随手记状态保存失败，过期标记未生效（详见日志）", kind: .error, duration: 5.0)
        }
    }

    private func ensureDirectory() -> Bool {
        let dir = fileURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                logError("persist", "InboxService 父路径不是目录 \(dir.path)")
                return false
            }
            return true
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return true
        } catch {
            logError("persist", "InboxService 创建目录失败 \(dir.path): \(error.localizedDescription)")
            return false
        }
    }
}
