import Foundation
import SwiftUI

// Notion 配置管理
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

    func syncFromNotion() async {
        isSyncing = true
        defer { isSyncing = false }

        // 通过 ChatEngine + MCP 查询
        let calendarQuery = """
        查询 Notion Calendar 数据库中的今日和未来事件，返回事件名称、开始时间和结束时间。
        """

        do {
            let mcpPath = Bundle.main.path(forResource: "notion-mcp", ofType: "json")
            if calendarDbId.isEmpty {
                // 只测试连接
                isConnected = true
            } else {
                _ = try await ChatEngine.shared.sendMessageWithMCP(
                    calendarQuery,
                    systemPrompt: AppState.shared.systemPrompt,
                    mcpConfigPath: mcpPath
                )
                isConnected = true
            }
            lastSyncTime = Date()
        } catch {
            isConnected = false
        }
    }

    func addCalendarEvent(_ event: TaskItem) async {
        guard !calendarDbId.isEmpty else { return }

        let addQuery = """
        在 Notion Calendar 数据库中添加事件：\(event.title)，开始时间：\(formatDate(event.timerStart)),结束时间：\(formatDate(event.timerEnd)))
        """

        do {
            let mcpPath = Bundle.main.path(forResource: "notion-mcp", ofType: "json")
            _ = try await ChatEngine.shared.sendMessageWithMCP(
                addQuery,
                systemPrompt: AppState.shared.systemPrompt,
                mcpConfigPath: mcpPath
            )
        } catch {
            // 忽略错误
        }
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}