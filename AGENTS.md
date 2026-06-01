# OPC 伴侣 - 开发指令

## 项目概述

macOS 原生菜单栏 AI 助手应用。Swift + SwiftUI + AppKit 混合架构，Swift Package Manager 构建。

## 技术栈

- **语言：** Swift 6.3
- **UI：** SwiftUI（视图层）+ AppKit（NSPanel, NSStatusItem, NSEvent）
- **语音：** Speech framework (SFSpeechRecognizer) + AVFoundation (AVSpeechSynthesizer)
- **AI 后端：** MiniMax API（`MiniMax-M2.7` 模型），URLSession HTTPS 直连，流式 + function calling
- **Notion：** Notion API v1 直连（URLSession，HTTP）
- **凭证：** macOS Keychain（API key 与 Notion token，绝不明文落盘）
- **构建：** Swift Package Manager → build.sh 打包为 .app bundle
- **最低系统：** macOS 15.0+

## 架构约束

### 双 UI 模式

1. **主面板（NSPanel）：** 屏幕居中的浮层窗口，Option+Space 触发。承载所有主动交互（对话、任务、设置）。
2. **菜单栏（NSStatusItem + NSPopover）：** 右上角常驻图标。只承载状态展示和被动提醒通知。

两者共享同一个 AppState（@Observable / ObservableObject），数据始终同步。

### MiniMax 调用规范

```swift
// Endpoint
let url = URL(string: "https://api.minimax.io/v1/text/chatcompletion_v2")!

// Request body
let body: [String: Any] = [
    "model": "MiniMax-M2.7",
    "messages": messagesHistory,   // system/user/assistant/tool 完整历史
    "tools": toolsDefinition,      // function calling
    "stream": true,
    "max_tokens": 2048,
    "temperature": 0.7
]

// Headers
request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
```

- 流式响应（`URLSession.bytes` / SSE），首 token 尽快渲染
- messages 在本地维护，每次带完整（或按 token 预算截断）历史
- Tool call 执行完追加 `role: "tool"` 消息，再次请求 MiniMax 生成最终文本
- 写操作（如 Notion create/update）必须先经 UI 确认，不在 Service 内直接执行

### 数据目录

所有持久化数据存放在 `~/.opc-companion/`，不要存在 app bundle 内或其他位置。
结构见 PRD.md §7。

## 代码规范

### 文件组织

```
Sources/OPCCompanion/
├── App/          # 入口 + AppDelegate（菜单栏、热键、窗口管理）
├── Views/        # SwiftUI 视图，按 Tab 分子目录
├── Services/     # 业务逻辑（无 UI 依赖，可独立测试）
├── Models/       # 数据模型（Codable struct）
└── Utils/        # 工具类
```

### 命名

- 文件名 = 主类型名（如 `ChatEngine.swift` 包含 `class ChatEngine`）
- SwiftUI 视图以 `View` 结尾
- Service 类以 `Service` 或 `Manager` 结尾
- 使用 Swift 原生命名约定（camelCase 属性，PascalCase 类型）

### 并发

- 使用 Swift Concurrency（async/await, @MainActor）
- UI 更新必须在 @MainActor
- 网络调用用 `URLSession.bytes` / `AsyncThrowingStream` 处理流式响应
- 语音识别回调通过 @MainActor 回到主线程

### UI 规范

- 严格遵循 macOS Human Interface Guidelines
- 使用系统语义色，不硬编码颜色值
- 使用 SF Symbols，不引入自定义图标资源
- 支持深色/浅色模式自动切换（全部使用系统色即可）
- 间距使用 8pt 网格系统
- 动画使用 SwiftUI .animation 或 withAnimation，参数见 PRD.md §9.3

### 错误处理

- MiniMax 调用失败 → 在对话中显示友好错误消息，不 crash
- Notion 连接失败 → 设置页状态变红，对话中提示用户检查配置
- 语音权限拒绝 → 弹出引导用户去系统偏好设置开启
- 所有错误包含定位信息（文件名 + 函数名 + 错误描述）

## 构建和运行

```bash
# 开发构建
swift build

# 打包为 .app 并运行
./build.sh

# 清理
swift package clean
```

build.sh 负责：
1. `swift build -c release`
2. 创建 OPCCompanion.app/Contents/{MacOS, Resources} 目录
3. 复制二进制到 MacOS/
4. 复制 Info.plist 到 Contents/
5. 复制 AppIcon.icns 到 Resources/
6. 用 ad-hoc 签名：`codesign -s - OPCCompanion.app`

## 关键实现细节

### 全局快捷键

使用 NSEvent.addGlobalMonitorForEvents 监听 Option+Space：
- keyDown + flagsChanged 组合判断
- 短按（< 500ms）= 切换面板
- 长按（≥ 500ms）= 语音模式，keyUp 时停止录音并发送

### 中央面板窗口

- 使用 NSPanel（level: .floating, styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView]）
- 隐藏标题栏，使用 titlebarAppearsTransparent + titleVisibility = .hidden
- 背景用 NSVisualEffectView（material: .hudWindow, blendingMode: .behindWindow）
- 居中定位：相对于当前活跃屏幕居中

### Notion 写操作确认流程

1. MiniMax 返回 `create_notion_page` 等写操作 tool call
2. ChatEngine 识别是写操作，**不立即执行**，把 tool call 传给 UI 层
3. UI 显示确认卡片（内嵌在对话流中，不是弹窗）
4. 用户点击"确认" → ChatEngine 调用 NotionService 执行，结果作为 `role: "tool"` 追加后再次请求 MiniMax
5. 用户点击"取消" → 在对话中显示"已取消"

### 定时任务调度

- App 启动时加载 scheduled.json，为每个任务计算下次触发时间
- 使用 Timer.scheduledTimer 或 DispatchSourceTimer
- 每分钟检查一次是否有任务需要触发
- 触发时：UNUserNotificationCenter.add() + 对话插入系统消息 + 菜单栏红点
