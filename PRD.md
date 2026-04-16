# OPC 伴侣 - 产品需求文档 (PRD)

## 1. 产品概述

OPC 伴侣是一个常驻 macOS 的 AI 工作节奏教练。它通过快捷键唤起的中央浮层面板提供主动交互，通过菜单栏提供被动状态监控和提醒通知，帮助用户管理工作节奏、跟踪任务进度、接入 Notion 数据。

**目标用户：** 独立创作者 / 内容工作者，日常使用 Notion 管理任务和日程，需要 AI 辅助保持专注和节奏。

**技术栈：** Swift (SwiftUI + AppKit)，macOS 原生应用，Claude CLI 作为 AI 后端。

---

## 2. 双 UI 架构

### 2.1 主面板（中央浮层）— 主动交互

**触发方式：** Option+Space 全局快捷键

**表现形式：**
- 屏幕正中弹出的浮层窗口（NSPanel，类似 Spotlight / Raycast）
- 尺寸：宽 420px，高 560px
- 背景使用 macOS 原生毛玻璃材质（NSVisualEffectView / .ultraThinMaterial）
- 圆角 16px，带轻微阴影
- 弹出/收起时带 macOS 原生缩放 + 淡入淡出动画

**快捷键行为：**
- 面板关闭时，按 Option+Space → 面板弹出，光标聚焦输入框
- 面板打开时，按 Option+Space → 面板关闭
- 面板打开时，长按 Option+Space → 进入语音输入模式，松手发送
- 按 Escape → 关闭面板
- 点击面板外部 → 关闭面板

### 2.2 菜单栏（右上角）— 被动提醒

**表现形式：**
- 常驻 macOS 菜单栏的状态图标（SF Symbol: bubble.left.fill）
- 图标颜色随状态变化（见 §5）
- 有新提醒时图标旁显示红色小圆点

**提醒交互：**
- 定时提醒到达 → 菜单栏图标加红点 + macOS 系统通知（UNUserNotificationCenter）
- 点击菜单栏图标 → 下拉小型 NSPopover（宽 320px，高 ≤200px）展示提醒摘要
- 点击提醒摘要中的"查看详情" → 打开中央主面板

---

## 3. 主面板布局

### 3.1 三个 Tab 页

面板底部 Tab 栏，使用 SF Symbols 图标 + 文字标签，遵循 macOS Tab 设计规范。

#### Tab 1: 对话（默认）

```
┌──────────────────────────────────────┐
│  📋 当日任务                    ▼ 折叠 │
│  ┌────────────────────────────────┐  │
│  │ ○ 写口播稿            🟢 25:00 │  │
│  │ ○ 回复社群消息                  │  │
│  │ ● 整理日报              ✓ 完成  │  │
│  └────────────────────────────────┘  │
├──────────────────────────────────────┤
│                                      │
│  对话消息流（可滚动，新消息在底部）     │
│                                      │
│  ┌─ 用户 ─────────────────────────┐  │
│  │ 帮我看看今天的日程              │  │
│  └────────────────────────────────┘  │
│  ┌─ OPC ──────────────────────────┐  │
│  │ 你今天有 3 个安排：             │  │
│  │ 14:00 团队周会                  │  │
│  │ 16:00 客户沟通                  │  │
│  └────────────────────────────────┘  │
│                                      │
├──────────────────────────────────────┤
│ ┌──────────────────────┐  🎤   ⏎   │
│ │ 输入文字...            │           │
│ └──────────────────────┘            │
├──────────────────────────────────────┤
│   💬 对话    │   📅 历史   │   ⚙ 设置 │
└──────────────────────────────────────┘
```

**当日任务区（置顶）：**
- 默认展开，可点击折叠/展开
- 显示当日所有任务，未完成在前，已完成（灰色+删除线）在后
- 如果某个任务正在计时，显示倒计时数字和状态色圆点
- 任务列表数据来源：本地 pinned.json + 可通过对话添加/完成

**对话区：**
- 消息气泡样式，用户消息靠右（蓝色调），AI 消息靠左（灰色调）
- 支持 Markdown 渲染（至少支持加粗、列表、代码块）
- 新消息自动滚动到底部
- AI 回复过程中显示打字指示器（三个跳动的圆点）

**输入栏：**
- 文字输入框（NSTextField），支持多行（Shift+Enter 换行，Enter 发送）
- 麦克风按钮（SF Symbol: mic.fill）
  - 未录音：灰色
  - 录音中：红色 + 脉冲动画
- 发送按钮（SF Symbol: arrow.up.circle.fill），有输入内容时高亮

#### Tab 2: 历史

```
┌──────────────────────────────────────┐
│  📅 对话历史                          │
│                                      │
│  ┌─ 日期列表 ─────────────────────┐  │
│  │ 📅 2026-04-15 (今天)  12条消息  │  │
│  │ 📅 2026-04-14         8条消息   │  │
│  │ 📅 2026-04-13         15条消息  │  │
│  │ ...                             │  │
│  └────────────────────────────────┘  │
│                                      │
│  点击某天 → 展开该天对话内容          │
│  （与对话 Tab 相同的消息气泡样式）     │
│                                      │
├──────────────────────────────────────┤
│   💬 对话    │   📅 历史   │   ⚙ 设置 │
└──────────────────────────────────────┘
```

- 按日期倒序显示（最近在前）
- 每天一行：日期 + 消息条数
- 点击某天 → 原地展开该天的完整对话内容（可折叠回去）
- 只读浏览，不可编辑

#### Tab 3: 设置

```
┌──────────────────────────────────────┐
│  ⚙ 设置                              │
│                                      │
│  ┌─ 系统提示词 ───────────────────┐  │
│  │                                │  │
│  │ 多行文本编辑区域               │  │
│  │ （自动保存）                    │  │
│  │                                │  │
│  └────────────────────────────────┘  │
│                                      │
│  ┌─ 定时任务 ─────────────────────┐  │
│  │ 每日复盘         18:00  每天    │  │
│  │ 周计划           09:00  每周一  │  │
│  │                    [+ 添加]    │  │
│  └────────────────────────────────┘  │
│                                      │
│  ┌─ 连接状态 ─────────────────────┐  │
│  │ Notion   🟢 已连接              │  │
│  │ Claude CLI  🟢 可用             │  │
│  └────────────────────────────────┘  │
│                                      │
├──────────────────────────────────────┤
│   💬 对话    │   📅 历史   │   ⚙ 设置 │
└──────────────────────────────────────┘
```

**系统提示词：**
- 多行文本编辑器（NSTextView），monospace 字体
- 输入后自动保存（debounce 1 秒）
- 默认预填一段通用提示词（见 §8）

**定时任务管理：**
- 列表展示所有定时任务
- 每行：任务名 + 时间 + 周期 + 启用/禁用开关
- 点击某行 → 弹出编辑表单（Sheet）
- [+ 添加] 按钮 → 新建任务表单
- 任务表单字段：
  - 名称（文本）
  - 时间（TimePicker）
  - 周期（Picker：每天 / 每周一~日 / 自定义 cron）
  - 提醒内容（文本，发送给 AI 的 prompt）
  - 启用/禁用开关

**连接状态：**
- 显示 Notion 和 Claude CLI 的连接状态
- 绿色圆点 = 正常，红色 = 异常

---

## 4. 交互流程

### 4.1 文字对话

1. 用户按 Option+Space，面板弹出，光标在输入框
2. 用户打字，按 Enter 发送
3. 消息显示在对话区（用户侧）
4. 显示"正在思考..."打字指示器
5. 调用 Claude CLI 获取回复
6. 回复以文字显示在对话区（AI 侧）
7. 不触发语音朗读

### 4.2 语音对话

1. 用户按 Option+Space，面板弹出
2. 用户长按 Option+Space（或点击麦克风按钮）
3. 麦克风按钮变红 + 脉冲动画，开始录音
4. SFSpeechRecognizer 实时转写，文字显示在输入框中
5. 用户松开按键（或再次点击麦克风），停止录音
6. 转写文字自动发送
7. 调用 Claude CLI 获取回复
8. 回复以文字显示 + AVSpeechSynthesizer 语音朗读（同时进行）

### 4.3 定时提醒

1. 到达定时任务设定的时间
2. 菜单栏图标加红点
3. 发送 macOS 系统通知（标题："OPC 伴侣"，内容：任务提醒文字）
4. 在对话中插入一条系统消息："⏰ [任务名] — [提醒内容]"
5. 用户可以：
   - 点击系统通知 → 打开主面板
   - 点击菜单栏图标 → 看提醒摘要
   - 按 Option+Space → 打开主面板继续对话

### 4.4 专注计时

1. 用户在对话中说"开始 XX 任务，25 分钟"
2. AI 解析意图，创建计时任务
3. 任务出现在置顶任务区，显示倒计时
4. 菜单栏图标变绿（专注中）
5. 80% 时间到（20 分钟）→ 图标变黄，对话中插入提醒
6. 100% 时间到 → 图标变红，菜单栏红点 + 系统通知 + 对话提醒
7. 用户回复"完成了" → 任务标记完成，图标恢复灰色
8. 用户回复"再给我 10 分钟" → 延长计时

### 4.5 Notion 操作

**读取操作（无需确认）：**
1. 用户说"看看我今天的日程" / "查一下待办"
2. MiniMax 返回 function call（`query_notion_database`）
3. App 直接调用 Notion API 执行
4. 结果回传给 MiniMax 生成自然语言摘要
5. 显示在对话中

**写入操作（需要确认）：**
1. 用户说"帮我加一条待办：写周报"
2. MiniMax 返回 function call（`create_notion_page`）
3. App 拦截该 function call，**不立即执行**，而是在面板显示确认卡片：
   ```
   ┌─ 即将执行 Notion 操作 ──────────┐
   │ 操作：新增页面                    │
   │ 数据库：每日待办                  │
   │ 内容：写周报                     │
   │                                  │
   │     [ 取消 ]    [ ✓ 确认执行 ]   │
   └──────────────────────────────────┘
   ```
4. 用户点击"确认执行"或说"确认"
5. 执行操作，反馈结果

---

## 5. 菜单栏状态系统

### 5.1 状态定义

| 状态 | 图标颜色 | SF Symbol | 触发 | 退出 |
|------|---------|-----------|------|------|
| idle | 系统默认色 | bubble.left.fill | 默认 / 任务完成 | 开始任务 |
| focus | 绿色 | bubble.left.fill | 用户开始计时 | 时间到 / 完成 |
| warning | 黄色 | bubble.left.fill | 计时剩余 ≤20% | 时间到 |
| overtime | 红色 | bubble.left.fill | 计时结束未完成 | 用户完成/取消 |
| rest | 蓝色 | bubble.left.fill | 用户说"休息" | 用户回来 |

### 5.2 通知红点

- 有未读提醒时，图标右上角叠加一个红色小圆点（直径 6px）
- 用户打开主面板查看后，红点消失

---

## 6. 数据模型

### 6.1 对话消息 (Message)

```json
{
  "id": "uuid",
  "role": "user | assistant | system",
  "content": "消息文本",
  "timestamp": "2026-04-15T14:30:00+08:00",
  "input_mode": "text | voice",
  "metadata": {}
}
```

### 6.2 任务条目 (TaskItem)

```json
{
  "id": "uuid",
  "title": "写口播稿",
  "status": "pending | in_progress | done | cancelled",
  "timer_minutes": 25,
  "timer_start": "2026-04-15T14:00:00+08:00",
  "timer_end": "2026-04-15T14:25:00+08:00",
  "extensions": 0,
  "created_at": "2026-04-15T14:00:00+08:00"
}
```

### 6.3 定时任务配置 (ScheduledTask)

```json
{
  "id": "uuid",
  "name": "每日复盘",
  "time": "18:00",
  "schedule": "daily | weekly:monday | cron:0 18 * * *",
  "prompt": "提醒我做今天的复盘，回顾完成了哪些任务",
  "enabled": true
}
```

### 6.4 全局配置 (Config)

```json
{
  "hotkey": "option+space",
  "quick_capture_hotkey": "option+`",
  "system_prompt_file": "~/.opc-companion/system-prompt.txt",
  "ai": {
    "provider": "minimax",
    "endpoint": "https://api.minimax.io/v1/text/chatcompletion_v2",
    "model": "M2-her",
    "api_key_keychain": "com.shiye.opc-companion.minimax-key",
    "max_tokens": 2048,
    "temperature": 0.7
  },
  "notion": {
    "api_version": "2022-06-28",
    "token_keychain": "com.shiye.opc-companion.notion-token",
    "database_ids": {
      "calendar": "数据库ID",
      "todos": "数据库ID",
      "inbox": "数据库ID"
    }
  },
  "voice": {
    "tts_voice": "com.apple.voice.compact.zh-CN.Tingting",
    "tts_rate": 0.5
  }
}
```

**安全要求：** API Key（MiniMax 和 Notion token）必须存储在 macOS Keychain，不能以明文写入 config.json。config.json 只存储 Keychain 中的条目名。

---

## 7. 数据存储

```
~/.opc-companion/
├── config.json                # 全局配置
├── system-prompt.txt          # 系统提示词（纯文本，方便编辑）
├── conversations/
│   ├── 2026-04-15.jsonl       # 每天一个文件，每行一条 Message JSON
│   └── 2026-04-14.jsonl
├── tasks/
│   └── pinned.json            # 当日置顶任务列表 [TaskItem]
└── timers/
    └── scheduled.json         # 定时任务配置列表 [ScheduledTask]
```

---

## 8. 默认系统提示词

```
你是 OPC 伴侣，一个 macOS 上的个人工作节奏教练。

你的职责：
1. 帮助用户管理工作节奏：计时、提醒、任务跟踪
2. 通过 Notion 查看和管理用户的日程与待办
3. 在用户偏离计划时主动提醒
4. 回复简洁直接，不要啰嗦

回复规则：
- 使用中文
- 简短有力，每次回复控制在 3 句话以内
- 需要执行具体操作时，调用相应的 function（见 tools 定义）
- Notion 写入类操作由用户 UI 确认，你只需发起 function call
```

**通过 Function Calling（Tools）发起结构化操作，不再用文本标记。**


---

## 9. AI 后端与 Function Calling

### 9.1 AI 后端：MiniMax

- **Endpoint：** `https://api.minimax.io/v1/text/chatcompletion_v2`
- **认证：** `Authorization: Bearer <API_KEY>` header
- **模型：** `M2-her`（MiniMax 最新对话模型，支持 function calling）
- **对话维护：** 本地保存 messages 数组，每次请求带完整历史（或截断至最近 N 轮）
- **流式响应：** `stream: true`，UI 实时渲染，体验比等整句更流畅

### 9.2 Function Calling / Tools 定义

所有 AI 可以发起的结构化操作，必须声明为 tools：

| Tool 名称 | 用途 | 需要确认 | 参数 |
|----------|------|---------|------|
| `start_timer` | 开始一个计时任务 | 否 | `task: string`, `minutes: int` |
| `complete_timer` | 标记当前计时任务完成 | 否 | `note?: string` |
| `extend_timer` | 延长当前计时 | 否 | `minutes: int` |
| `query_notion_database` | 查询 Notion 数据库 | 否 | `database_key: string`, `filter?: object` |
| `create_notion_page` | 新增 Notion 页面 | **是** | `database_key: string`, `properties: object` |
| `update_notion_page` | 修改 Notion 页面 | **是** | `page_id: string`, `properties: object` |
| `add_pinned_task` | 添加一条置顶任务 | 否 | `title: string` |
| `review_inbox` | 打开随手记收件箱 | 否 | 无 |

**执行流程：**
1. MiniMax 返回 `tool_calls` 数组
2. 对每个 tool call，Swift 侧判断是否需要确认
3. 需要确认的 → UI 弹出确认卡片，用户确认后执行
4. 不需要确认的 → 立即执行
5. 执行结果作为 `role: "tool"` 的消息追加到历史，再次请求 MiniMax
6. MiniMax 生成最终自然语言回复展示给用户

### 9.3 Notion 直连 API

- **Base URL：** `https://api.notion.com/v1`
- **认证：** `Authorization: Bearer <NOTION_TOKEN>` + `Notion-Version: 2022-06-28`
- **关键 endpoints：**
  - `POST /databases/{id}/query` — 查询数据库
  - `POST /pages` — 新建页面
  - `PATCH /pages/{id}` — 更新页面属性
  - `GET /pages/{id}` — 读取页面

### 9.4 Notion Calendar 读取

Notion Calendar 本质是带日期属性的数据库，通过 `/databases/{id}/query` + date filter 读取：

```json
{
  "filter": {
    "property": "日期",
    "date": { "equals": "2026-04-15" }
  }
}
```

用户在设置页配置 calendar 对应的 database_id，读取时按日期 filter。

---

## 10. macOS 设计规范要求

整个应用必须严格遵循 Apple Human Interface Guidelines (HIG) for macOS：

### 10.1 视觉设计
- 使用 SF Symbols 作为所有图标
- 使用系统语义色（.primary, .secondary, .accent 等），支持浅色/深色模式自动切换
- 毛玻璃背景材质（NSVisualEffectView 或 SwiftUI .ultraThinMaterial）
- 圆角使用系统标准值（大容器 16px，卡片 12px，按钮 8px）
- 间距遵循 8pt 网格系统

### 10.2 组件设计
- 使用原生 SwiftUI 组件：Toggle, Picker, DatePicker, TextField, TextEditor
- Tab 栏使用 TabView 或自定义但符合 macOS tab 样式
- 列表使用 List 组件，支持原生选中和悬停效果
- 按钮使用 .bordered 或 .borderedProminent 样式
- 确认对话使用 .confirmationDialog 或自定义 Sheet

### 10.3 动画设计
- 面板弹出/收起：.spring(response: 0.3, dampingFraction: 0.8) 弹性动画
- 消息出现：从底部滑入 + 淡入，duration 0.2s
- 状态切换：颜色渐变 duration 0.3s
- 麦克风录音：红色脉冲动画 scaleEffect 1.0 ↔ 1.2，repeatForever
- Tab 切换：crossfade 过渡
- 任务完成：删除线从左到右绘制 + 颜色淡出

### 10.4 无障碍
- 所有交互元素设置 accessibilityLabel
- 支持 VoiceOver
- 支持键盘导航（Tab 切换焦点）

---

## 11. 验收标准

### P0（必须实现）

- [ ] Option+Space 全局快捷键唤起/关闭中央浮层面板
- [ ] 面板中可输入文字，发送后收到 MiniMax 回复（流式渲染）
- [ ] 长按 Option+Space 进入语音输入，AI 语音+文字回复
- [ ] 菜单栏常驻图标，颜色随状态变化
- [ ] 当日任务置顶显示，支持计时倒计时
- [ ] 对话历史按天持久化，可在历史 Tab 按日期查看
- [ ] 设置页可编辑系统提示词
- [ ] 深色/浅色模式自动适配

### P1（应该实现）

- [ ] 定时任务：设置页创建/编辑/删除定时提醒
- [ ] 定时到达时菜单栏红点 + 系统通知 + 对话插入提醒
- [ ] Notion 读取：通过对话查询 Notion 数据库
- [ ] Notion 写入：操作前在面板内展示确认卡片

### P2（可以后续迭代）

- [ ] Notion Calendar 自动同步到当日任务区
- [ ] 对话中 Markdown 富文本渲染
- [ ] 自定义快捷键
- [ ] 语音选择（TTS 声音切换）
- [ ] 每日工作总结自动生成
