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

    public func append(_ note: Note) {
        lock.lock()
        defer { lock.unlock() }
        ensureDirectory()

        guard let encoded = try? JSONEncoder().encode(note),
              let line = String(data: encoded, encoding: .utf8),
              let lineData = line.data(using: .utf8),
              let newlineData = "\n".data(using: .utf8) else { return }

        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(newlineData)
                handle.write(lineData)
            }
        } else {
            try? line.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    public func saveAll(_ notes: [Note]) {
        lock.lock()
        defer { lock.unlock() }
        ensureDirectory()

        let lines = notes.compactMap { note -> String? in
            guard let data = try? JSONEncoder().encode(note) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        let body = lines.joined(separator: "\n")
        try? body.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    public static var defaultURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".opc-companion/inbox/notes.jsonl")
    }

    /// 砍-A：扫描随手记，把 pending 且 capturedAt 距今 >48h 的标记为 .expired。
    /// state 的 notes 数组同步更新，便于 UI 实时反映。
    @MainActor
    public func expirePendingNotesOlderThan48h(state: AppState) {
        let cutoff = Date().addingTimeInterval(-48 * 3600)
        var changed = false
        for i in state.notes.indices where state.notes[i].status == .pending && state.notes[i].capturedAt < cutoff {
            state.notes[i].status = .expired
            state.notes[i].processedAt = Date()
            changed = true
        }
        if changed {
            saveAll(state.notes)
        }
    }

    private func ensureDirectory() {
        let dir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
