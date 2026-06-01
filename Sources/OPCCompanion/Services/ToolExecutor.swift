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
                "description": "调整当前计时任务的剩余时间。分钟数正数为延长、负数为缩短（例 -5 = 缩短 5 分钟）。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "minutes": ["type": "integer", "description": "正数延长 / 负数缩短，范围 -60 至 120，非 0"]
                    ],
                    "required": ["minutes"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "cancel_timer",
                "description": "取消当前活跃计时（任务置 cancelled，释放 activeTask）。用户明确说'算了不做了'、'取消当前任务'时调用。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "reason": ["type": "string", "description": "可选：一句话解释取消原因"]
                    ]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "mark_task_done",
                "description": "按标题标记一条 pinned task 为已完成（不影响活跃计时，用于用户口头汇报'X 做完了'）。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "任务标题的完整或包含文本"]
                    ],
                    "required": ["title"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "delete_pinned_task",
                "description": "按标题删除一条 pinned task（用户说'把 X 去掉'/'删了那条'时调用）。已完成的任务不会被删，需用 mark_task_done 反向。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "任务标题的完整或包含文本"]
                    ],
                    "required": ["title"]
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
        // update_notion_page 已关闭（用户要求：不可删除、不可更新、可新写入、可读取）
        [
            "type": "function",
            "function": [
                "name": "get_tasks",
                "description": "获取用户当前的任务列表。可按状态过滤。返回任务标题、状态、预估/实际时长等。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "status": ["type": "string", "enum": ["pending", "in_progress", "done", "cancelled", "all"], "description": "过滤状态，默认 all"]
                    ]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "get_inbox_notes",
                "description": "获取用户的随手记列表。可按状态过滤。返回内容、捕获时间、来源。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "status": ["type": "string", "enum": ["pending", "done", "expired", "all"], "description": "过滤状态，默认 pending"]
                    ]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "get_today_daily_note",
                "description": "获取今天的 daily note 内容（包含任务完成记录、定时触发、随手记、学习候选等）。",
                "parameters": ["type": "object", "properties": [:]]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "get_scheduled_tasks",
                "description": "获取用户配置的定时提醒列表。返回名称、时间、周期、提示词、是否启用。",
                "parameters": ["type": "object", "properties": [:]]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "memory_search",
                "description": "在用户的记忆系统（长期记忆 MEMORY.md、用户画像 USER.md、历史 daily note）中按关键词检索。返回匹配片段 + 来源日期。适用于用户问'上周我聊过 X 吗'、'我有没有记过关于 Y 的事'。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "搜索关键词"]
                    ],
                    "required": ["query"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "end_wish_clearing",
                "description": "结束当前的 /聊聊 Wish Clearing 会话。在用户说'先到这'/'回去了'/'回工作'或你完成状态回放后必须调用。未调用会导致后续普通对话被 wish 上下文污染。",
                "parameters": ["type": "object", "properties": [:]]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "log_wish_decision",
                "description": "在 /聊聊 Wish Clearing 模式里，**每当你和用户对一条 wish 做出决策后必须调用**。记录到今日 daily note 并执行副作用：升级为任务/立即做 会把 wish 升级成今日 pinned；删除 会直接删除；先留着 只留痕不改变数据。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "wish_content": [
                            "type": "string",
                            "description": "该条 wish 的完整原文或前 20 字（用于匹配本地 note）"
                        ],
                        "decision": [
                            "type": "string",
                            "enum": ["立即做", "升级为任务", "先留着", "删除"],
                            "description": "立即做 / 升级为任务 = 把 wish 加进今日 pinned（不自动起计时，让用户手动开始）；先留着 = 保留 wish，只把讨论结果写入 daily note；删除 = 彻底删除这条 wish"
                        ],
                        "reason": [
                            "type": "string",
                            "description": "可选：一句话解释为什么这么决策（便于周报和回溯）"
                        ]
                    ],
                    "required": ["wish_content", "decision"]
                ]
            ]
        ]
    ] }

    /// 需要 UI 确认才执行的 tool
    public static let requiresConfirmation: Set<String> = [
        "create_notion_page"
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
            // Guard：已有活跃计时时不静默 overwrite，返回 conflict 让 AI 主动询问用户
            if let active = state.activeTask, active.status == .inProgress {
                return errorResult("已有活跃计时 [\(active.title)]，请先 complete_timer / cancel_timer 再起新计时")
            }
            guard state.startTimer(task: task, minutes: minutes) != nil else {
                return errorResult("计时任务保存失败，请重试")
            }
            return successResult(["task": task, "minutes": minutes])

        case "complete_timer":
            let note = args["note"] as? String
            guard state.completeCurrentTimer(note: note) else {
                return errorResult("当前没有活跃计时，或完成状态保存失败")
            }
            return successResult([:])

        case "extend_timer":
            guard let minutes = args["minutes"] as? Int, minutes != 0 else {
                return errorResult("分钟数不能为 0")
            }
            guard state.extendCurrentTimer(by: minutes) else {
                return errorResult("当前没有活跃计时，或计时调整保存失败")
            }
            return successResult(["minutes": minutes])

        case "cancel_timer":
            guard state.activeTask != nil else {
                return errorResult("当前没有活跃计时可取消")
            }
            let reason = args["reason"] as? String
            guard state.cancelCurrentTimer(reason: reason) else {
                return errorResult("取消计时保存失败，请重试")
            }
            return successResult(["cancelled": true])

        case "mark_task_done":
            guard let title = args["title"] as? String, !title.isEmpty else {
                return errorResult("title 缺失")
            }
            if let done = state.markPinnedTaskDoneByTitle(title) {
                return successResult(["matched": done.title])
            }
            return errorResult("未找到匹配的 pending 任务：\(title)")

        case "delete_pinned_task":
            guard let title = args["title"] as? String, !title.isEmpty else {
                return errorResult("title 缺失")
            }
            if let removed = state.deletePinnedTaskByTitle(title) {
                return successResult(["removed": removed.title])
            }
            return errorResult("未找到匹配任务：\(title)")

        case "add_pinned_task":
            guard let title = args["title"] as? String, !title.isEmpty else {
                return errorResult("标题为空")
            }
            guard state.addPinnedTask(title: title) != nil else {
                return errorResult("任务保存失败，请重试")
            }
            return successResult(["title": title])

        case "review_inbox":
            state.openInbox()
            return successResult(["pending_count": state.unreadNoteCount])

        case "get_tasks":
            return executeGetTasks(args: args, state: state)

        case "get_inbox_notes":
            return executeGetInboxNotes(args: args, state: state)

        case "get_today_daily_note":
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            let content = MemoryService.shared.readDaily(date: Date())
            return successResult(["date": f.string(from: Date()), "content": content.isEmpty ? "今天暂无记录" : content])

        case "get_scheduled_tasks":
            let items = state.scheduledTasks.map { t -> [String: Any] in
                ["name": t.name, "time": t.time, "schedule": "\(t.schedule)", "prompt": t.prompt, "enabled": t.enabled]
            }
            return successResult(["count": items.count, "tasks": items])

        case "query_notion_database":
            return await executeQueryNotion(args: args)

        case "create_notion_page":
            return await executeCreateNotion(args: args)

        case "update_notion_page":
            return errorResult("update_notion_page 已关闭，当前只允许读取和新建")

        case "memory_search":
            guard let query = args["query"] as? String, !query.isEmpty else {
                return errorResult("搜索词为空")
            }
            return executeMemorySearch(query: query)

        case "end_wish_clearing":
            let hadSession = state.wishClearingSession != nil
            state.endWishClearingSession()
            return successResult(["ended": hadSession])

        case "log_wish_decision":
            guard let content = (args["wish_content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty,
                  let decisionRaw = (args["decision"] as? String) else {
                return errorResult("wish_content 或 decision 缺失")
            }
            let decision = decisionRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            let reason = (args["reason"] as? String) ?? ""
            return executeLogWishDecision(content: content, decision: decision, reason: reason, state: state)

        default:
            return errorResult("未知工具：\(call.function.name)")
        }
    }

    @MainActor
    private static func executeLogWishDecision(content: String, decision: String, reason: String, state: AppState) -> String {
        // 本地 wish 匹配：先找 content 完全相等的，再退化到前缀匹配
        let matchingNote = state.notes.first(where: { n in n.kind == .wish && n.content == content })
            ?? state.notes.first(where: { n in n.kind == .wish && n.content.hasPrefix(content) })

        // daily note 条目用中文术语
        let entry = "我想清扫 → \(decision)：\(content)\(reason.isEmpty ? "" : "（\(reason)）")"

        var effect = "已记录"
        // 兼容中英文术语（enum 已改中文，但保留英文别名以防 AI 带习惯）
        switch decision {
        case "删除", "delete":
            if let note = matchingNote {
                guard state.deleteNote(note) else {
                    return errorResult("随手记删除失败，请重试")
                }
                effect = "已删除"
            }
        case "立即做", "升级为任务", "now", "promote":
            if let note = matchingNote {
                guard state.promoteNoteToPinnedTask(note, title: content) else {
                    return errorResult("随手记升级任务失败，请重试")
                }
            } else if state.addPinnedTask(title: content) == nil {
                return errorResult("任务保存失败，请重试")
            }
            effect = "已升级为今日任务"
        case "先留着", "defer":
            effect = "已留存"
        default:
            break
        }
        MemoryService.shared.appendToToday(.notes, entry: entry)
        return successResult(["decision": decision, "effect": effect, "matched": matchingNote != nil])
    }

    @MainActor
    private static func executeGetTasks(args: [String: Any], state: AppState) -> String {
        let statusFilter = args["status"] as? String ?? "all"
        let filtered: [TaskItem]
        if statusFilter == "all" {
            filtered = state.tasks
        } else if let s = TaskStatus(rawValue: statusFilter == "in_progress" ? "in_progress" : statusFilter) {
            filtered = state.tasks.filter { $0.status == s }
        } else {
            filtered = state.tasks
        }
        let items: [[String: Any]] = filtered.map { t in
            var d: [String: Any] = ["title": t.title, "status": t.status.rawValue]
            if let m = t.timerMinutes { d["estimate_minutes"] = m }
            if let a = t.actualMinutes { d["actual_minutes"] = a }
            if let r = t.remainingSeconds { d["remaining_seconds"] = r }
            return d
        }
        return successResult(["count": items.count, "tasks": items])
    }

    @MainActor
    private static func executeGetInboxNotes(args: [String: Any], state: AppState) -> String {
        let statusFilter = args["status"] as? String ?? "pending"
        let filtered: [Note]
        if statusFilter == "all" {
            filtered = state.notes.filter { $0.status != .deleted }
        } else if let s = Note.Status(rawValue: statusFilter) {
            filtered = state.notes.filter { $0.status == s }
        } else {
            filtered = state.notes.filter { $0.status == .pending }
        }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        let items: [[String: String]] = filtered.map { n in
            ["content": n.content, "captured_at": f.string(from: n.capturedAt), "source": n.source.rawValue, "status": n.status.rawValue]
        }
        return successResult(["count": items.count, "notes": items])
    }

    @MainActor
    private static func executeMemorySearch(query: String) -> String {
        let memoryDir = AppState.dataDirectory.appendingPathComponent("memory")
        let fm = FileManager.default
        var results: [[String: String]] = []
        let keywords = query.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !keywords.isEmpty else { return errorResult("关键词为空") }

        let enumerator = fm.enumerator(at: memoryDir, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)
            let source = url.deletingPathExtension().lastPathComponent
            for (lineNum, line) in lines.enumerated() {
                let lower = line.lowercased()
                if keywords.allSatisfy({ lower.contains($0) }) {
                    results.append([
                        "source": source,
                        "line": String(lineNum + 1),
                        "text": line.trimmingCharacters(in: .whitespaces)
                    ])
                    if results.count >= 20 { break }
                }
            }
            if results.count >= 20 { break }
        }

        if results.isEmpty {
            return successResult([
                "matches": 0,
                "message": "未找到匹配：\(query)",
                "hint": "未命中不代表用户没记过；可尝试换同义词、拆分关键词或扩大时间窗再搜，搜不到就坦诚说'没在记忆里匹配到'而不要断言'不存在'"
            ])
        }
        return successResult(["matches": results.count, "results": results])
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
