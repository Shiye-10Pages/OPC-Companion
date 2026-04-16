# OPC 伴侣 - API 接入指南

本文档给出 MiniMax 和 Notion 两个外部 API 的具体接入范例，供实现时参考。

---

## 一、MiniMax Chat Completion API

### 1.1 基本信息

- **Endpoint：** `POST https://api.minimax.io/v1/text/chatcompletion_v2`
- **Auth：** `Authorization: Bearer <API_KEY>`
- **模型：** `M2-her`

### 1.2 最简请求示例

```json
POST https://api.minimax.io/v1/text/chatcompletion_v2
Authorization: Bearer xxxxx
Content-Type: application/json

{
  "model": "M2-her",
  "messages": [
    {"role": "system", "content": "你是 OPC 伴侣..."},
    {"role": "user", "content": "帮我开始一个 25 分钟的专注任务：写口播稿"}
  ],
  "stream": false,
  "max_tokens": 2048,
  "temperature": 0.7
}
```

### 1.3 带 Tools（Function Calling）的请求

```json
{
  "model": "M2-her",
  "messages": [...],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "start_timer",
        "description": "开始一个计时任务",
        "parameters": {
          "type": "object",
          "properties": {
            "task": {"type": "string", "description": "任务名称"},
            "minutes": {"type": "integer", "description": "计时分钟数"}
          },
          "required": ["task", "minutes"]
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "query_notion_database",
        "description": "查询 Notion 数据库",
        "parameters": {
          "type": "object",
          "properties": {
            "database_key": {
              "type": "string",
              "enum": ["calendar", "todos", "inbox"],
              "description": "数据库标识"
            },
            "date_filter": {
              "type": "string",
              "description": "日期过滤：today / this_week / YYYY-MM-DD"
            }
          },
          "required": ["database_key"]
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "create_notion_page",
        "description": "在 Notion 数据库中新建页面。此操作需要用户确认后才执行。",
        "parameters": {
          "type": "object",
          "properties": {
            "database_key": {"type": "string", "enum": ["calendar", "todos", "inbox"]},
            "properties": {"type": "object", "description": "页面属性"}
          },
          "required": ["database_key", "properties"]
        }
      }
    }
  ],
  "stream": true
}
```

### 1.4 带 tool_calls 的响应示例

```json
{
  "choices": [{
    "message": {
      "role": "assistant",
      "content": "好的，我来帮你开始专注任务。",
      "tool_calls": [{
        "id": "call_abc123",
        "type": "function",
        "function": {
          "name": "start_timer",
          "arguments": "{\"task\":\"写口播稿\",\"minutes\":25}"
        }
      }]
    }
  }]
}
```

### 1.5 Tool 执行后回传给 MiniMax

```json
{
  "model": "M2-her",
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user", "content": "帮我开始一个 25 分钟的专注任务：写口播稿"},
    {
      "role": "assistant",
      "content": "好的，我来帮你开始专注任务。",
      "tool_calls": [{
        "id": "call_abc123",
        "type": "function",
        "function": {"name": "start_timer", "arguments": "{\"task\":\"写口播稿\",\"minutes\":25}"}
      }]
    },
    {
      "role": "tool",
      "tool_call_id": "call_abc123",
      "content": "{\"status\":\"success\",\"timer_id\":\"t_xyz\",\"end_time\":\"2026-04-15T14:25:00+08:00\"}"
    }
  ]
}
```

MiniMax 再根据 tool result 生成最终回复："已开始 25 分钟计时，14:25 提醒你。"

### 1.6 流式响应处理

`stream: true` 时响应为 SSE 格式，每行 `data: {...}` 一个 JSON chunk：

```
data: {"choices":[{"delta":{"content":"好的"}}]}
data: {"choices":[{"delta":{"content":"，我来帮你"}}]}
data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_abc"}]}}]}
data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"start_timer"}}]}}]}
data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"task\""}}]}}]}
...
data: [DONE]
```

Swift 侧用 `URLSession.bytes(for:)` 流式读取，按行解析。

### 1.7 Swift 封装示意

```swift
actor MiniMaxClient {
    let apiKey: String
    let endpoint = URL(string: "https://api.minimax.io/v1/text/chatcompletion_v2")!

    func chat(messages: [Message], tools: [Tool]) -> AsyncThrowingStream<ChatChunk, Error> {
        // 构造请求，stream: true
        // URLSession.bytes 逐行解析 SSE
        // 每个 chunk yield 给调用方
    }
}
```

---

## 二、Notion API

### 2.1 基本信息

- **Base URL：** `https://api.notion.com/v1`
- **Auth：** `Authorization: Bearer <NOTION_TOKEN>`
- **必需 Header：** `Notion-Version: 2022-06-28`
- **Content-Type：** `application/json`

### 2.2 查询数据库（Calendar 读取示例）

```json
POST https://api.notion.com/v1/databases/{database_id}/query

{
  "filter": {
    "property": "Date",
    "date": {
      "equals": "2026-04-15"
    }
  },
  "sorts": [
    {"property": "Date", "direction": "ascending"}
  ]
}
```

返回：
```json
{
  "results": [
    {
      "id": "page_id_xxx",
      "properties": {
        "Title": {"title": [{"plain_text": "团队周会"}]},
        "Date": {"date": {"start": "2026-04-15T14:00:00+08:00"}}
      }
    }
  ]
}
```

### 2.3 新建页面（Notion 写操作）

```json
POST https://api.notion.com/v1/pages

{
  "parent": {"database_id": "xxx"},
  "properties": {
    "Name": {
      "title": [{"text": {"content": "写周报"}}]
    },
    "Status": {
      "select": {"name": "Todo"}
    },
    "Due Date": {
      "date": {"start": "2026-04-19"}
    }
  }
}
```

### 2.4 更新页面属性

```json
PATCH https://api.notion.com/v1/pages/{page_id}

{
  "properties": {
    "Status": {
      "select": {"name": "Done"}
    }
  }
}
```

### 2.5 获取数据库 schema（帮助用户选择 database_id）

```
GET https://api.notion.com/v1/databases/{database_id}
```

返回数据库的 properties schema，设置页可用来展示可用字段，让用户做映射配置。

---

## 三、凭证管理

### 3.1 用户首次配置流程

1. App 启动检测 Keychain 中是否有 `minimax-api-key` 和 `notion-token`
2. 若没有 → 设置页弹出配置界面
3. 用户填入 API Key / Notion Token → 调用 Keychain API 存储
4. 存储成功后，测试一次 API 连通性（MiniMax 发个 hello，Notion 拉一次 user info）
5. 显示绿色「已连接」状态

### 3.2 Keychain 存取封装

```swift
enum KeychainHelper {
    static let service = "com.shiye.opc-companion"

    static func save(key: String, value: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: value.data(using: .utf8)!
        ]
        SecItemDelete(query as CFDictionary)  // 先删旧的
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }
}
```

### 3.3 使用

```swift
KeychainHelper.save(key: "minimax-api-key", value: userInput)
let apiKey = KeychainHelper.load(key: "minimax-api-key")
```

---

## 四、Notion 数据库映射配置

### 4.1 问题

App 不知道用户 Notion 中哪个数据库是"日历"、哪个是"待办"。

### 4.2 方案

在设置页提供一个"Notion 数据库映射"区域：

```
Notion 数据库绑定
├─ 日历  →  [选择数据库...] ▼
├─ 待办  →  [选择数据库...] ▼
└─ 收件箱（用于推送随手记）→ [选择数据库...] ▼
```

点击下拉 → 通过 Notion API `POST /search` 列出用户所有可访问的数据库 → 用户选择 → 存入 `config.json` 的 `notion.database_ids`。

### 4.3 搜索数据库

```json
POST https://api.notion.com/v1/search

{
  "filter": {"value": "database", "property": "object"}
}
```

返回用户可访问的所有数据库列表。

---

## 五、常用错误与重试策略

| 场景 | 处理 |
|------|------|
| MiniMax 429（限流） | 指数退避重试，最多 3 次 |
| MiniMax 网络超时 | 15 秒超时，失败提示用户 |
| Notion 401 | Token 无效，提示重新配置 |
| Notion 404 | database_id 错误，提示检查映射 |
| Notion 429 | Notion 限流较宽松，遇到时等 1 秒再试 |
| 流式响应中途断开 | 保留已收到的内容，追加「[连接中断]」标记 |

