import Foundation

/// 把 MiniMax 返回的 tool_call 分派到 AppState 对应方法，返回 role=tool 要求的 content（JSON 字符串）。
public enum ToolExecutor {
    /// 本次可供 AI 调用的 tools（二期仅本地 tool；Notion 相关延后到三期）。
    public static var availableTools: [[String: Any]] { [
        [
            "type": "function",
            "function": [
                "name": "start_timer",
                "description": "开始一个计时任务，用户进入专注状态。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "task": ["type": "string", "description": "任务名称"],
                        "minutes": ["type": "integer", "description": "计时分钟数，1-240"]
                    ],
                    "required": ["task", "minutes"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "complete_timer",
                "description": "标记当前正在进行的计时任务完成。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "note": ["type": "string", "description": "可选备注"]
                    ]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "extend_timer",
                "description": "延长当前计时任务。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "minutes": ["type": "integer", "description": "延长的分钟数，1-120"]
                    ],
                    "required": ["minutes"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "add_pinned_task",
                "description": "在当日任务区添加一条待办（不自动开始计时）。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "任务标题"]
                    ],
                    "required": ["title"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "review_inbox",
                "description": "切换到收件箱 Tab，用户将看到未处理的随手记。",
                "parameters": ["type": "object", "properties": [:]]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "query_notion_database",
                "description": "查询 Notion 数据库。database_key 从 calendar/todos/inbox 中选。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "database_key": [
                            "type": "string",
                            "enum": ["calendar", "todos", "inbox"]
                        ],
                        "filter": [
                            "type": "object",
                            "description": "Notion API 查询 filter，原样透传"
                        ]
                    ],
                    "required": ["database_key"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "create_notion_page",
                "description": "在 Notion 数据库新建页面。此操作需要用户确认。properties 按 Notion API 规范构造。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "database_key": [
                            "type": "string",
                            "enum": ["calendar", "todos", "inbox"]
                        ],
                        "properties": ["type": "object"]
                    ],
                    "required": ["database_key", "properties"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "update_notion_page",
                "description": "更新 Notion 页面属性。此操作需要用户确认。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "page_id": ["type": "string"],
                        "properties": ["type": "object"]
                    ],
                    "required": ["page_id", "properties"]
                ]
            ]
        ]
    ] }

    /// 需要 UI 确认才执行的 tool
    public static let requiresConfirmation: Set<String> = [
        "create_notion_page",
        "update_notion_page"
    ]

    @MainActor
    public static func execute(_ call: WireToolCall) async -> String {
        logInfo("tool", "execute \(call.function.name) args=\(call.function.arguments)")
        let state = AppState.shared
        let args = parseArgs(call.function.arguments)

        switch call.function.name {
        case "start_timer":
            guard let task = args["task"] as? String, !task.isEmpty,
                  let minutes = args["minutes"] as? Int, minutes > 0 else {
                return errorResult("参数无效")
            }
            state.startTimer(task: task, minutes: minutes)
            return successResult(["task": task, "minutes": minutes])

        case "complete_timer":
            let note = args["note"] as? String
            state.completeCurrentTimer(note: note)
            return successResult([:])

        case "extend_timer":
            guard let minutes = args["minutes"] as? Int, minutes > 0 else {
                return errorResult("分钟数无效")
            }
            state.extendCurrentTimer(by: minutes)
            return successResult(["minutes": minutes])

        case "add_pinned_task":
            guard let title = args["title"] as? String, !title.isEmpty else {
                return errorResult("标题为空")
            }
            state.addPinnedTask(title: title)
            return successResult(["title": title])

        case "review_inbox":
            state.openInbox()
            return successResult(["pending_count": state.unreadNoteCount])

        case "query_notion_database":
            return await executeQueryNotion(args: args)

        case "create_notion_page":
            return await executeCreateNotion(args: args)

        case "update_notion_page":
            return await executeUpdateNotion(args: args)

        default:
            return errorResult("未知工具：\(call.function.name)")
        }
    }

    @MainActor
    private static func executeQueryNotion(args: [String: Any]) async -> String {
        let state = AppState.shared
        guard let key = args["database_key"] as? String,
              let dbId = state.config.notionDatabaseIds.id(for: key),
              !dbId.isEmpty else {
            return errorResult("数据库未配置：请到设置页绑定 \(args["database_key"] ?? "")")
        }

        let filter = args["filter"] as? [String: Any]
        let body: [String: Any] = filter.map { ["filter": $0] } ?? [:]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            return errorResult("filter 序列化失败")
        }

        do {
            let respData = try await NotionService.shared.queryDatabase(databaseId: dbId, bodyData: bodyData)
            let json = (try? JSONSerialization.jsonObject(with: respData) as? [String: Any]) ?? [:]
            let results = json["results"] as? [[String: Any]] ?? []
            return successResult(["count": results.count, "results": results])
        } catch {
            return errorResult(error.localizedDescription)
        }
    }

    @MainActor
    private static func executeCreateNotion(args: [String: Any]) async -> String {
        let state = AppState.shared
        guard let key = args["database_key"] as? String,
              let dbId = state.config.notionDatabaseIds.id(for: key),
              !dbId.isEmpty else {
            return errorResult("数据库未配置：请到设置页绑定 \(args["database_key"] ?? "")")
        }
        guard let properties = args["properties"] as? [String: Any],
              let propertiesData = try? JSONSerialization.data(withJSONObject: properties, options: []) else {
            return errorResult("缺少或无法序列化 properties")
        }

        do {
            let respData = try await NotionService.shared.createPage(databaseId: dbId, propertiesData: propertiesData)
            let json = (try? JSONSerialization.jsonObject(with: respData) as? [String: Any]) ?? [:]
            let pageId = json["id"] as? String ?? ""
            return successResult(["page_id": pageId])
        } catch {
            return errorResult(error.localizedDescription)
        }
    }

    @MainActor
    private static func executeUpdateNotion(args: [String: Any]) async -> String {
        guard let pageId = args["page_id"] as? String, !pageId.isEmpty else {
            return errorResult("缺少 page_id")
        }
        guard let properties = args["properties"] as? [String: Any],
              let propertiesData = try? JSONSerialization.data(withJSONObject: properties, options: []) else {
            return errorResult("缺少或无法序列化 properties")
        }
        do {
            _ = try await NotionService.shared.updatePage(pageId: pageId, propertiesData: propertiesData)
            return successResult(["page_id": pageId])
        } catch {
            return errorResult(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private static func parseArgs(_ arguments: String) -> [String: Any] {
        guard let data = arguments.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    private static func successResult(_ payload: [String: Any]) -> String {
        var obj = payload
        obj["status"] = "success"
        return jsonString(obj)
    }

    private static func errorResult(_ message: String) -> String {
        return jsonString(["status": "error", "message": message])
    }

    private static func jsonString(_ obj: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
              let str = String(data: data, encoding: .utf8) else {
            return #"{"status":"error","message":"encoding failed"}"#
        }
        return str
    }
}
