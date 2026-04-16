import Foundation
import SwiftUI

// 三期接入 NotionService 直连后重构；当前只保留数据库 id 配置的持久化入口。
@MainActor
final class NotionSyncManager: ObservableObject {
    static let shared = NotionSyncManager()

    @Published var calendarDbId: String = ""
    @Published var todosDbId: String = ""
    @Published var isConnected = false
    @Published var isSyncing = false
    @Published var lastSyncTime: Date?

    private init() {
        loadConfig()
    }

    private func loadConfig() {
        let config = AppState.shared.config
        calendarDbId = config.notionDatabaseIds.calendar ?? ""
        todosDbId = config.notionDatabaseIds.todos ?? ""
    }

    func saveConfig() {
        var config = AppState.shared.config
        config.notionDatabaseIds.calendar = calendarDbId
        config.notionDatabaseIds.todos = todosDbId
        AppState.shared.config = config
        AppState.shared.saveConfig()
    }
}
