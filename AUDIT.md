# OPC 伴侣 全量审计与修复记录

审计时间: 2026-06-01
方法: 5 个 agent 并行全量代码审计 + `swift test` + `./build.sh`
范围: 重构后的双入口产品 —— Quiet Field 前门（默认）/ 经典三胶囊面板（可选），由 `config.entryMode` 切换

## 状态
- 单元测试: **85 通过 / 0 失败**
- Release 构建: **通过**
- GUI 自动化: 无（自定义 NSPanel 浮窗无法稳定驱动，本次为代码审计 + 单测）

---

## 已修复（本轮）

### 🔴 安全
- **凭证改用 Keychain**：废弃明文 `secrets.json`。启动时把历史明文迁进 Keychain 后删除明文文件；迁移加护栏（Keychain 确实写成功才删文件，防凭证丢失）。`Utils/CredentialCache.swift`。配套测试改为断言安全不变量（绝不明文落盘 / 迁移后删文件）。
  - **行为变化**：ad-hoc 签名下首次访问 key 时 macOS 弹一次「允许访问钥匙串」→ 点「始终允许」；重打包后签名身份变可能再弹。这是安全的必要代价。
- **删除 OPCLogger 自动写 Notion 错误上报**：端掉「绕过确认 + 硬编码 DB id」的旁路；错误仍进本地日志文件 + stderr。`Utils/Logger.swift`。

### 🟠 P1
- TaskCard 排序改为合法严格弱序（进行中置顶）。`Views/Components/MainTabView.swift`
- `handleSpaceChange` 切桌面时补关 Quiet Field 前门（原先只关主面板 + QuickCapture）。`App/AppDelegate.swift`
- `打开面板 / 设置 / 通知点击` 按 `entryMode` 分流（quietField 用户不再被踢回经典面板）。`App/AppDelegate.swift`
- cron 定时任务：确认 UI 无入口（`ScheduleType` 仅 daily/weekly），建不出来 → 无需改。

### 🟡 P2 / 🟢 P3
- 文案修正：`ChatView` welcomeTips、`InboxView` 不再宣传已删的 Option+\` / 长按语音。
- 死代码清理：`TaskSection`、`ToolExecutor.executeUpdateNotion`、`MessageRole.chatCompletionRole`、两个调试菜单方法、`QuietFieldShell.primaryLine` 死分支。

### 不吞异常（CLAUDE.md「不吞异常」合规）
- `MemoryService` 三处 `try?` 静默写失败 → do/catch + `OPCLogger.error`。
- `WeeklyArchiveService` 周报生成失败 → warn 升 error + 失败 banner。
- `VoiceService` 语音识别错误 → 补 `isRecording = false` + 失败 banner（不再只闷在日志）。

---

## 待办 / 未处理（按原因）

| 项 | 原因 | 建议 |
|---|---|---|
| 模型名 `MiniMax-M2.7`(代码) vs `M2-her`(CLAUDE.md) | 不确定哪个对、改了怕断 API | **需确认**正确模型名后统一代码 + 文档 |
| wabi / flow 主题 = Aurora 占位 | 实现两套完整主题是大工程 | 按需再做，或从主题选择器先隐藏 |
| 经典面板内部重复入口（清扫 5 处 / 一键整理 2 处 / 双重未锁定提示） | 经典模式是保留的旧版，改动有回归风险 | 保留现状 |
| `Note.Status.deleted` / `Action` / `NotionAction` 枚举 | 删 Codable 枚举值 / 可能被测试引用，有风险 | 保留 |
| progressPing 折叠态不可见 | 设计取舍（折叠 bar 保持纯粹） | 保留 |

---

## 功能清单（按能力域）

完整逐条清单见会话审计记录。能力域：

入口与窗口（菜单栏 / 双入口模式 / 热键） · Quiet Field 前门（记一下 / 聊聊 / 卷帘展开 / 浮念分拣 / 清扫 / 收束 / 设置 / 主题动画背景 / 主动浮层） · 经典三胶囊面板 · 对话 AI（MiniMax 流式 + function calling + 斜杠命令） · 任务与计时（Pomodoro / 专注模式） · 随手记 / 浮念 / 收件箱 · 我想清扫 · 记忆与归档（daily / 周报 / 跨日 / Dreaming） · 主动介入（早晨仪式 / 偏离 / 深夜 / 进展 ping） · 语音（STT / TTS） · Notion（读 / 写需确认） · 主题与视觉（5 主题 / 4 字体） · 配置与持久化（Keychain 凭证 / `~/.opc-companion/`）
