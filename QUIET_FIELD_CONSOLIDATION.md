# Quiet Field 收敛方案（定稿）

> 状态：**方案已定，待实施。仍未动代码。**
> 一句话：**折叠极简 bar（记录 + 清扫入口）⇄ 展开完整面板（classic 优化版，自由对话 + 全功能）。单面板·两高度。主题保留。**

---

## 1. 目标架构

```
┌─ 折叠态：极简单行 bar ───────────────────────┐
│  [tray] 记一下想法…                  「聊聊」 ⌄ │   ← 随手记输入 + 清扫入口 + 展开
└──────────────────────────────────────────────┘
                      ↓ 展开（同一前门长高到 classic 体量）
┌─ 展开态：完整面板（classic 基础，修复优化） ──┐
│  上方：纯状态区（焦点 / 计时 / 浮念数）—— 无交互 │
│  ───────────────────────────────────────────── │
│  此刻（自由对话 ChatView） / 浮念 / 收束 / 设置  │
│  全功能：晨间仪式·任务管理·定时表单·清扫桌·各介入 │
│  主题动画背景保留                                │
└──────────────────────────────────────────────┘
```

- **折叠态**：保留极简 bar 的精神（快速记录）。一行输入存随手记 + 一个「聊聊（清扫）」按钮 + 展开。
- **展开态**：直接呈现 **classic 完整面板的体量与布局**（修复后），而不是现在 `QuietFieldShell` 那个 460 高的简化卷帘层。
- **两者是同一前门的两个高度**，不是两套 UI。

---

## 2. 命名规范（消除"同词不同功能"）

| 词 | 指什么 | 入口 | 走不走 AI |
|---|---|---|---|
| **随手记** | 快速记录碎片 | 折叠 bar 输入 | 否（纯本地） |
| **此刻** | 和 AI 自由对话 | 展开面板主体（`ChatView`） | 是 |
| **聊聊** | 限时清扫积压随手记 | 折叠 bar 按钮 / `/聊聊` / 展开面板入口 | 是 |
| ~~我想~~ | **废除** | — | — |

> 自由对话默认不单独起动词名，就归在「此刻」里（打开面板打字即对话）。如需专名再议。

---

## 3. 处置清单

| 处置 | 对象 | 说明 |
|---|---|---|
| ✅ 保留 | 极简 bar 折叠态（`QuietFieldShell` 的折叠部分） | 折叠 bar 的输入 + 展开机制 |
| ✅ 保留 | `MainTabView` 完整面板及其内容 | 作为展开态基础，需理干净 |
| ✅ 保留 | `ChatView`（自由对话）、`InboxView`、`HistoryView`、`SettingsView`、`QuietWishClearingDesk`、各介入子视图、主题系统 | — |
| 🔧 改造 | 折叠 ⇄ 展开接成同一前门（窗口管理） | 现在 `QuietFieldShell` 与主面板是两个独立 NSPanel，需合一 |
| 🔧 改造 | 上方区域 → 纯状态（见 §6） | `QuietMomentDashboard` 去交互 |
| 🔧 改造 | 折叠 bar：去掉"随手记⇄聊聊"切换，改为「随手记输入 + 聊聊(清扫)按钮」 | [QuietFieldShell.swift:333](Sources/OPCCompanion/Views/Components/QuietFieldShell.swift:333) |
| ❌ 退役 | `QuietFieldShell` 的卷帘展开层：`dashboardHeader` / `conversation` / 5 个 screen 的简化实现 | 被 classic 完整面板取代 |
| ❌ 退役 | `.wish` / "我想"全链路（见 §4） | — |
| ⚖️ 评估 | `QuietMomentDashboard` / `FloatingThoughtsScene` / `ClosureScene` 外壳 | 保留壳但清空交互，还是并入新结构，实施时定 |

---

## 4. 数据层改动：移除 `.wish`（"我想"）

> **决策：采纳方案 A** —— 不保留任何"不过期"机制，长期念头一律当随手记（48h 过期，`expired` 仍可在清扫捞回）。`Note.Kind` 整个移除。

清扫对象从此变成 **"积压的随手记"**。已知改动点（实施前用 `grep wish/我想` 全量复核）：

- [Note.swift:67](Sources/OPCCompanion/Models/Note.swift:67)：**整个 `Kind` 移除**（只剩随手记一种）。旧 `notes.jsonl` 里的 `.wish` 记录反序列化时忽略 `kind` 字段、自动变普通随手记——正是 A 预期；实施时确认 decoder 容错（现 [Note.swift:44](Sources/OPCCompanion/Models/Note.swift:44) 已有 `decodeIfPresent`）
- [InboxService.swift:102](Sources/OPCCompanion/Services/InboxService.swift:102)：48h 过期去掉 `kind != .wish` 排除 → 所有 pending 随手记统一过期
- [AppState.swift:779](Sources/OPCCompanion/Services/AppState.swift:779)：清扫候选排序去掉 wish 优先
- [QuickCaptureView.swift:32](Sources/OPCCompanion/Views/QuickCapture/QuickCaptureView.swift:32)：去掉 `isWish` 切换（此组件去留随窗口合并一并定）
- `ChatEngine.swift:367/371`、`InboxView.swift:300`、`QuietFieldViews.swift:189/290`、`SettingsView.swift:93` 隐私文案：清理 "我想" 文案与计数

---

## 5. "聊聊" = 清扫

- `/聊聊` 命令、system prompt 的 Wish Clearing 协议（[AppState.swift:1589](Sources/OPCCompanion/Services/AppState.swift:1589)）保留，**对象改成随手记**，文案去"我想"。
- 折叠 bar 的「聊聊」按钮 = 展开并进入清扫。
- classic「此刻」里那个「聊聊」按钮（[QuietFieldViews.swift:73](Sources/OPCCompanion/Views/Components/QuietFieldViews.swift:73)）语义已统一为清扫，保留或随上方区域改造一起处理。

---

## 6. 上方区域：只读状态，不留交互

- `QuietMomentDashboard` 现在「3 指标 + 完成/延长/记一下/整理浮念/聊聊 一排按钮」混排 → **只保留状态展示**（当前焦点 / 计时倒数 / 浮念数），回到类似 `StatusBar` 的纯状态逻辑。
- 被拿掉的交互去哪：
  - 「完成 / 延长」计时操作 → 移到计时卡片或对话区顶部（实施时定位）
  - 「记一下」→ 折叠 bar 已承担
  - 「整理浮念 / 聊聊」→ 走场所导航 / 折叠 bar 按钮

---

## 7. 技术风险与牵连

- **窗口合并**是最大改造点：`QuietFieldShell`（独立 panel，524 宽）与主面板 `ContentView`（760×620）现在分属两个 NSPanel，要变成"一个 panel 两个高度"或"折叠 bar 触发同一 panel 长高"。
- `selectedTab` 5 个 case 需随结构梳理。
- `entryMode` 开关：收敛后是直接移除、还是留 classic 作回退一段时间，待定。
- **只动 UI 结构 + 命名 + 移除 .wish；不碰** notes.jsonl 持久化格式之外的数据流、AI 调用、归档逻辑。

---

## 8. 建议落地顺序（小步、各步可单独验证）

1. **数据层**：移除 `.wish`，清扫对象改随手记，清文案。（最底层，先做）
2. **命名**：统一"聊聊=清扫"，自由对话归「此刻」。
3. **上方区域状态化**：`QuietMomentDashboard` 去交互。
4. **窗口合并**：折叠 bar ⇄ classic 完整面板接成同一前门，退役 `QuietFieldShell` 卷帘层。
5. **清理**：删退役视图，收尾 `entryMode` / `selectedTab`。

---

## 9. 剩余待定（实施细节，非阻塞）

- 折叠 ⇄ 展开的具体实现形式（同 panel 改尺寸 vs 切换）与动画
- 上方状态区里"完成/延长"计时操作的最终落点
- `entryMode` 与 `QuickCaptureView` 的最终去留
- 自由对话是否要专门命名
