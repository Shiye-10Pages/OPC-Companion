# OPC 伴侣 - 开发指令

## 项目概述

macOS 原生菜单栏 AI 助手应用。Swift + SwiftUI + AppKit 混合架构，Swift Package Manager 构建。

## 技术栈

- **语言：** Swift 6.3
- **UI：** SwiftUI（视图层）+ AppKit（NSPanel, NSStatusItem, NSEvent）
- **语音：** Speech framework (SFSpeechRecognizer) + AVFoundation (AVSpeechSynthesizer)
- **AI 后端：** MiniMax API（`MiniMax-M2.7` 模型，HTTPS 直连）
- **Notion：** Notion API v1 直连（HTTP）
- **HTTP：** URLSession（不引入第三方库）
- **凭证：** macOS Keychain（API key 和 Notion token）
- **构建：** Swift Package Manager → build.sh 打包为 .app bundle
- **最低系统：** macOS 15.0+

## 架构约束

### 双 UI 模式

1. **主面板（NSPanel）：** 屏幕居中的浮层窗口，Option+Space 触发。承载主动交互（对话、任务、收件箱、设置）。
2. **菜单栏（NSStatusItem + NSPopover）：** 右上角常驻图标。承载状态展示和被动提醒通知。
3. **快捷输入条（NSPanel）：** 屏幕顶部浮出的单行输入框，Option+` 触发，用于随手记捕获。

三者共享同一个 AppState（@Observable），数据始终同步。

### AI 调用规范（MiniMax）

```swift
// Endpoint
let url = URL(string: "https://api.minimax.io/v1/text/chatcompletion_v2")!

// Request body
let body: [String: Any] = [
    "model": "MiniMax-M2.7",
    "messages": messagesHistory,        // 包含 system/user/assistant/tool 的完整历史
    "tools": toolsDefinition,           // function calling tools
    "stream": true,                     // 流式响应
    "max_tokens": 2048,
    "temperature": 0.7
]

// Headers
request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
```

**关键约定：**
- 流式响应必须支持，首 token 要能在 500ms 内显示给用户
- messages 数组在本地维护，每次请求带完整（或按 token 预算截断）
- Tool call 返回后，执行完追加 `role: "tool"` 消息，再次请求 MiniMax 生成最终文本
- Tool 的完整定义见 PRD.md §9.2

### Notion 调用规范

```swift
var request = URLRequest(url: URL(string: "https://api.notion.com/v1/databases/\(dbId)/query")!)
request.httpMethod = "POST"
request.setValue("Bearer \(notionToken)", forHTTPHeaderField: "Authorization")
request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
```

**写操作必须先经过 UI 确认**，不要在 NotionService 里直接执行 create/update。流程：
1. AI 返回 `create_notion_page` tool call
2. ChatEngine 识别是写操作，**不立即执行**
3. 把 tool call 传给 UI 层，展示确认卡片
4. 用户确认 → ChatEngine 调用 NotionService 执行
5. 执行结果作为 tool response 追加到 messages，再次请求 MiniMax

### 凭证存储

**绝不**把 API key 或 Notion token 明文写入任何文件。使用 Keychain：

```swift
// 存
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrAccount as String: "minimax-api-key",
    kSecAttrService as String: "com.shiye.opc-companion",
    kSecValueData as String: apiKey.data(using: .utf8)!
]
SecItemAdd(query as CFDictionary, nil)
```

设置页提供 API key 输入界面，写入 Keychain。config.json 只存 Keychain 条目的 account 名。

### 数据目录

所有持久化数据存放在 `~/.opc-companion/`，结构见 PRD.md §7 + PRD-QUICKCAPTURE.md §5.3。

## 代码规范

### 文件组织

```
Sources/OPCCompanion/
├── App/          # 入口 + AppDelegate（菜单栏、热键、窗口管理）
├── Views/        # SwiftUI 视图，按 Tab 分子目录
├── Services/     # 业务逻辑（无 UI 依赖）
├── Models/       # 数据模型（Codable struct）
└── Utils/        # 工具类（Keychain 封装、日志等）
```

核心 Services：
- `ChatEngine.swift` — 对话主逻辑，调用 MiniMax + 处理 tool calls
- `MiniMaxClient.swift` — MiniMax API 封装（HTTP、流式解析）
- `NotionService.swift` — Notion API 封装
- `VoiceManager.swift` — STT + TTS
- `TimerService.swift` — 计时 + 定时任务
- `StorageService.swift` — 本地持久化
- `KeychainHelper.swift` — Keychain 封装
- `InboxService.swift` — 随手记收件箱

### 命名

- 文件名 = 主类型名
- SwiftUI 视图以 `View` 结尾
- Service 类以 `Service` 或 `Manager` 或 `Client` 结尾

### 并发

- 使用 Swift Concurrency（async/await, @MainActor）
- UI 更新必须在 @MainActor
- 网络调用用 `URLSession.bytes` 或 `AsyncThrowingStream` 处理流式响应
- 语音识别回调通过 @MainActor 回到主线程

### UI 规范

- 严格遵循 macOS Human Interface Guidelines
- 使用系统语义色，不硬编码颜色值
- 使用 SF Symbols，不引入自定义图标资源
- 支持深色/浅色模式自动切换
- 间距使用 8pt 网格系统
- 动画参数见 PRD.md §10.3

### 错误处理

- MiniMax 调用失败 → 在对话中显示友好错误消息，不 crash
- Notion 调用失败 → tool response 返回错误，让 AI 自然告知用户
- 语音权限拒绝 → 弹出引导用户去系统偏好设置开启
- 网络断开 → 消息标记为"发送失败"，允许重试
- 所有错误包含定位信息（文件名 + 函数名 + 错误描述）

## 构建和运行

```bash
# 开发构建
swift build

# 打包为 .app 并运行
./build.sh
open OPCCompanion.app

# 清理
swift package clean
```

build.sh 负责：
1. `swift build -c release`
2. 创建 OPCCompanion.app/Contents/{MacOS, Resources} 目录
3. 复制二进制到 MacOS/
4. 复制 Info.plist 到 Contents/
5. 用 ad-hoc 签名：`codesign -s - OPCCompanion.app`

## 关键实现细节

### 全局快捷键

使用 `NSEvent.addGlobalMonitorForEvents`（`.keyDown` + `.flagsChanged`）：
- **Option+Space**：切换主面板显示/隐藏。长按 ≥500ms + 面板已打开 → 进入语音模式
- **Option+`**：呼出快捷输入条（随手记），自动开启录音

### 中央面板窗口

- `NSPanel` + `level: .floating` + `styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView]`
- 隐藏标题栏：`titlebarAppearsTransparent = true`，`titleVisibility = .hidden`
- 背景：`NSVisualEffectView`（`material: .hudWindow`，`blendingMode: .behindWindow`）
- 居中定位：相对于当前活跃屏幕（`NSScreen.main`）居中

### 快捷输入条窗口

- `NSPanel` + `level: .popUpMenu`（高于主面板）
- `styleMask: [.nonactivatingPanel, .borderless]`
- 位置：屏幕顶部居中，Y = 菜单栏高度 + 80px
- 背景毛玻璃 + 圆角 12px

### Function Calling 执行流程

```
User message
    ↓
MiniMax 返回 (流式)
    ├── 可能包含 text delta（直接渲染到 UI）
    └── 可能包含 tool_calls
         ↓
         for each tool_call:
            需要确认? ─ 是 ─→ UI 显示确认卡片 ─→ 用户确认 ─→ 执行
                    └─ 否 ─→ 立即执行
         ↓
         所有 tool_call 执行完毕，把结果作为 role: "tool" 追加到 messages
         ↓
         再次请求 MiniMax，生成最终自然语言回复
         ↓
         展示给用户
```

### Notion 写操作确认 UI

确认卡片嵌入在对话流中（不是系统弹窗）：
```
┌─ 即将执行 Notion 操作 ──────────┐
│ 操作：新增页面                    │
│ 数据库：每日待办                  │
│ 属性：                           │
│   - 标题: 写周报                  │
│   - 日期: 2026-04-15             │
│                                  │
│     [ 取消 ]    [ ✓ 确认执行 ]   │
└──────────────────────────────────┘
```

点击确认 → 调用 NotionService 执行 → 在原卡片位置替换为"✓ 已执行"或"✗ 失败：xxx"

### 定时任务调度

- App 启动时加载 scheduled.json，为每个启用任务计算下次触发时间
- 用 `Timer.scheduledTimer` 或 `DispatchSourceTimer`
- 每分钟检查一次是否有任务需要触发
- 触发时：`UNUserNotificationCenter.add()` + 对话插入系统消息 + 菜单栏红点

### 随手记捕获流程

1. Option+` 按下 → 快捷输入条弹出 + SFSpeechRecognizer 开始录音
2. 用户说话 → 实时转写到输入框
3. 如果用户在输入框敲键 → 停止录音，进入文字模式
4. 按回车 → 把输入内容写入 `~/.opc-companion/inbox/notes.jsonl`
5. 关闭输入条，菜单栏黄点 +1，播放轻微音效

**重要：** 随手记捕获完全不调用 MiniMax，纯本地操作。AI 只在用户主动打开收件箱后进入上下文。

## 安全要求

- 绝不提交 API key 或 Notion token 到 git
- .gitignore 必须包含 `~/.opc-companion/`、`.env`、`*.key`
- 所有凭证经 Keychain，config.json 只存引用
- Notion 写操作必须有用户确认环节，不能被绕过
