# 迭代推进文档 · 2026-05-27

> 主题：把 `bold-germain` 分支的 UI / 主题 / 交互方案 整合到主线 `feature/focused-conversation-memory`，并在用户实测过程中迭代修复一系列视觉、功能、可用性问题。
>
> 范围：commit `96388d4` (前一日里程碑 HEAD) → `2d147bf` (本日 HEAD)，**18 个 commit**。
> 配套文件：`EVAL_2026-05-27.md`（中段质量评估，commit `541164d` 时落地）、`.bug-investigations/2026-05-27-hotkey-failure.md`（顽固 bug 调查日志）。

---

## 0. 速览

| 维度 | 数字 |
|---|---|
| 总 commit 数 | 18 |
| 涉及文件 | 22 |
| 新增代码 | ~3,400 行 |
| 删除代码 | ~250 行 |
| 新增模块 | `Theme/` 主题系统、`FontStyle.swift` 字体方案、`HotkeyHealthMonitor.swift` 热键监测 |
| 测试通过 | 76 / 76 始终保持 |
| 部署形态 | 主线本地 → 推到 `origin/feature/focused-conversation-memory`，**已 push**，未 merge 到 main |
| 评估文档 | `EVAL_2026-05-27.md`（中段，含 7 条技术债 + 15 条手测清单） |

## 1. 这一轮的起点

进入这一日时的状态：

- **主线 HEAD**：`96388d4 feat: 我想功能 + 主动介入引擎 + 记忆跨天 + 状态条常驻 + 闭环加固`
- **功能完整度**：MiniMax function calling、随手记、Notion 直连、记忆系统、主动介入引擎、5 个 AppTab（chat/tasks/inbox/history/settings）等核心功能 OK
- **视觉欠缺**：UI 是 2026-04 时期的"工业风"，没有主题系统、没有入场动效、StatusBar + popover 范式
- **存在另一个分支** `claude/bold-germain-7e9306` —— 用户之前让别的 AI 在这上面做了完整的 UI / 主题 / 动效设计（Aurora + Stoa 双主题、3 胶囊导航、liquidIn 等），但这个分支的功能版本停留在 Claude CLI 时代，缺主线后续所有功能

**用户开场原话**：

> "我刚刚发现之前做的那个 UI 和交互的最新版本调整，并不是建立在最新功能版本的软件基础之上……所以我用另外一个 AI，把最新开发的 UI、动画、交互和最新的功能去做了一个新的结合。请评估结合的效果如何。"

—— 即：**用户期望以主线功能为基底，把 bold-germain 的 UI 集成进来**，让我评估别的 AI 做的集成质量。

## 2. 阶段拆解（按时间线）

### 阶段 A · 集成验证与回填（14:31 ~ 14:50，3 个 commit）

**触发**：用户说"另外那个 AI 集成完了，请评估"。
**意外发现**：实际状态是别的 AI 把 7 个 tracked 文件的修改放进了 git stash (`stash@{0}: epitaxy: pre-switch...`)，但 **9 个新增的 Theme/ 文件是 untracked 的**。看起来 stash 时漏了 untracked → 我误判为"文件丢了"。但 `git stash show --include-untracked` 后发现完整保留。**这是我的一个误诊** —— 由我开始多了一段绕路。

**实际操作**：
- 删掉我手动从 bold-germain 复制的同名文件
- `git checkout stash@{0}^3 -- Sources/OPCCompanion/Theme Sources/OPCCompanion/Views/Settings/ThemeSection.swift` 把 untracked 部分从 stash 的"第 3 父提交"取出
- `git stash pop` 恢复 tracked 修改
- 验证：`swift build` 通过、`swift test` 76/76、`./build.sh` OK

**收尾 commit**：
- `56f4b32 feat: 接入 Aurora / Stoa 主题系统 + 入场动效 + build 护栏`（17 文件、+1965/-59）
  - 主题系统 `Theme/` 完整搬入 + `AppConfig.themeID` 字段
  - ContentView 入场动效（背景淡入 + 内容偏移 + Aurora burst flash + watermark）
  - 输入框焦点保持（`focusInputSoon` 走 DispatchQueue 修 SwiftUI FocusState 时序）
  - build.sh 加 plutil/exec/codesign verify 三道护栏
  - MemoryServiceTests 修过期断言

**期间发现的 bug 1：API Key 不能粘贴**

> "我刚刚体验了一下，基本的功能还是有问题……设置当中的 API Key 窗口只能手动输入，不能粘贴。"

- **诊断**：`HUDPanel.styleMask = [.fullSizeContentView]`（历史为修启动卡死和保护中文 IME 精简过），无 `.titled` → AppKit 不为 panel 自动装载 field editor → Edit 菜单的 `paste:/copy:/cut:/selectAll:` 选择子无法通过响应链路由到 SwiftUI 内嵌的 `SecureField` / `TextField`
- **修复**：在 `HUDPanel` 和 `QuickCapturePanel` 重载 `performKeyEquivalent`，把 Cmd+V/C/X/A/Z 显式通过 `NSApp.sendAction(_, to: nil)` 派发。不依赖 styleMask，绕开 field editor 缺位
- **commit**：`495e8c6 fix: 修复 SecureField 在 HUDPanel 中无法粘贴`

### 阶段 B · 三胶囊导航 + 输入框多行 + 热键修复（14:47 ~ 15:23，4 个 commit）

**触发**：用户对集成后的 UI 不满意

> "目前主界面并没有按照之前最新的 UI 设计，上面应该有三个导航栏，而且目前的输入框气泡展示不完整。"
> "热键依旧不灵。"

**决策**：用户要求"调动多个 agent teammates 实现"。我先做诊断采集（看 bold-germain 的 NewTabBar、看 ChatView InputBar、看 hotkey 日志），然后**并行派出 2 个 agent**：

- **Agent A（worktree 隔离）**：UI 三胶囊重构 + 输入框 axis vertical 多行
- **Agent B（worktree 隔离）**：热键失效诊断 + 修复

#### Agent A 产出 — commit `b3e9cad`

- 设计取舍：**不动 `AppTab` 枚举**（动它会引爆 AppDelegate / PopoverView 多处调用）。MainTabView 内部新增 `@State private var visibleTab` 只在 chat/history/settings 三态间切换，与 5 case AppState 通过 onChange 双向 sync。任务 / 收件箱保留为 chat tab 上的 popover
- 输入框 `TextField(axis: .vertical) .lineLimit(1...6)`，新增 `onKeyPress(keys: [.return], phases: .down)` 显式拦截：单 Enter 发送，Shift+Enter 换行
- 所有 7 个 overlay（AddTask / MorningRitual / NextCandidates / PostMortem / ScheduledTask / DreamingReview / ProgressPing）作用域收紧到 `visibleTab == .chat`，切到历史 / 设置 tab 不再误闪
- StatusBar 移除历史按钮（升 tab 了）
- 删 `HistoryPopoverContent`（全局已无调用方）

#### Agent B 产出 — commit `3859aec` + `ec79a1d` + `541164d`

策略：**没有瞎修，先把诊断盲区补全**。原代码 `CarbonHotkeyManager.register` 未检查 `RegisterEventHotKey` 的 `OSStatus`，所有路径都"看起来成功"但 callback 不触发。

- `3859aec`：CarbonHotkeyManager 全链路加 OSStatus 校验 + dlog（`[CB] entry` / `[register] OK/FAILED` / `callbackEverFired` / 6s self-check）+ 调查日志 `.bug-investigations/2026-05-27-hotkey-failure.md`
- **复现实验**：用户按下 Option+Space → 看 grep `[hotkey]` 日志
  - 14:51:31 注册成功 (status=0)
  - 14:51:37 6s 自检：callback 从未触发
  - **12 分钟空白** → 15:03:30 突然开始工作
  - 用户「什么都没动，过了几分钟就好了」
- 根因**最可能是** macOS Secure Input mode（终端 sudo / 密码字段触发，第三方全局热键被系统层屏蔽，进程失焦后自动解除）—— 完美吻合「无操作 → 几分钟后自动好」
- `ec79a1d`：加入 `HotkeyHealthMonitor`（6s 初检 + 5s × 6 重检，最长 36s 监测窗口）+ Secure Input 监测（`IsSecureEventInputEnabled()`）+ 用户可见 Banner（区分 case A "系统启用了安全输入" / case B "其他启动器抢占"）+ 设置页「全局热键诊断」section（实时显示 snapshot + 一键重注册）
- `541164d`：清理冗余 log + 调查日志收尾为「已解决（缓解）」+ Agent C 写下 `EVAL_2026-05-27.md`（126 行，5 段评估）

### 阶段 C · 紧急修：面板高度（15:55，1 个 commit）

**触发**：用户截图，面板里三胶囊只露出底边、输入框只露出顶边，"显示不完整"。

**诊断**：ContentView ZStack 默认 `alignment: .center`，MainTabView 加入胶囊后自然高度 > 520pt，溢出向两端延伸，被 `visualEffectView.layer.masksToBounds=true` **对称剪裁**。

**修复**（`3d3f32a`）：
- panel + effectView + ContentView frame 三处 520 → 620
- MainTabView 加 `.frame(maxHeight: .infinity, alignment: .top)` 顶对齐
- ContentView 加 `.clipShape(panelCornerRadius)` 让溢出明确裁到圆角内
- 水印同步显示 760x620

### 阶段 D · 字体方案 + dark mode + 5 项视觉 polish（16:17 ~ 19:33，3 个 commit）

**触发**：用户系统对比"设计原意 vs 当前落地"——我列了 4 维度（字体/排版/交互/动画）共 7 条差距。用户决定一次性修。

#### `9db2f91` 补齐设计原意 5 项（高+中优先级）

bold-germain 设计的 5 个核心元素，主线集成时只接到了一半：

1. **`.transition(.liquidIn)`** 接到 MessageBubble / TypingIndicator
2. **LazyVStack `.spring(response: 0.5, dampingFraction: 0.78)` for messages.count + `.easeOut(0.35)` for isLoading**
3. **发送按钮** 从 iMessage 风 `arrow.up.circle.fill` 换成 **主题渐变 32×32 圆形 + `theme.accent` shadow** —— 接入"视觉锤"
4. **InputBar 顶部 InputKeyHint 条**（⌥Space VOICE / / CMD / ⇧⏎ NEWLINE / ⏎ SEND）
5. **输入框 focused shadow + easeInOut animation**

#### 用户 7 项视觉反馈（截图标注红框）

> "1. 面板圆角有多层，甚至有锐角  2. 输入框上下文字重叠，排版乱  3. 三胶囊与 StatusBar 过渡生硬  4. AI 气泡光影硬  5. 缺白天 / 黑夜切换  6. 按钮热区过小  7. 字体生硬"

字体方案让用户选→「**1 套可读 + 3 套艺术导向**」。

`cdc4ce8 fix: 6 项视觉 polish`：

1. **圆角分层**：visualEffectView.layer.cornerRadius 之前硬编码 16，主题 panelCornerRadius 是 26 (Aurora) / 4 (Stoa)，三层不一致。改：AppDelegate 加 `panelEffectView` 弱引用，ContentView 在 onAppear/主题切换时 `syncPanelCornerRadius`。**移除 ContentView 外层 clipShape**，让 effectView 做唯一裁切
2. **PanelWatermark 整段删** + hint 条 4 个简化为 1 个（右下 `⏎ SEND`，opacity 0.55）
3. StatusBar 去 ultraThinMaterial 背景 + 去 Divider，胶囊间距 6→14pt
4. **AI 气泡光影**：根因是 `bubbleAssistantStyle = .ultraThinMaterial`，但 panel 本身已是 ultraThinMaterial（visualEffectView material: .popover），**双层 material 叠加 → 光线穿透两次产生硬光斑**。改 Aurora `Color.white.opacity(0.42)`、Stoa 米白纸感
5. (由 832f0e4 提供)
6. **按钮热区**：StatusBar 30×26 → 36×32；mic / send 视觉 32×32 外圈 frame 40×40 + contentShape；TabButton 加 minHeight 32

`832f0e4 feat: 颜色方案 + 字体方案系统`：

- **新建 `Theme/FontStyle.swift`** —— 4 套字体方案（`readable / rounded / serif / display`），每套 7 类字体角色（body/title/mono/timestamp/systemMsg/strong/latin），通过 `Environment(\.fontStyle)` 注入，与主题色系**正交**（用户可独立选主题 + 字体）
- `FontStyleID.recommendedFor` 标记每套与哪个主题最配（设置页 UI 显示「· 推荐」角标）
- `ColorSchemeOverride` 枚举（system / light / dark）→ ContentView 顶层 `.preferredColorScheme`
- AppConfig 新增 `colorSchemeOverride` + `fontStyleID` 字段，自定义 Decoder 向后兼容旧 config
- 设置页 ThemeSection 追加：颜色方案分段控件 + 字体方案 2×2 卡片（每张卡片实时用对应字体渲染「Aa 你好 / 写稿 · 进展」预览）

### 阶段 E · Stoa 主题落地深挖（19:50 ~ 20:35，5 个 commit）

**触发**：用户

> "斯多葛模式下的 UI 主题和提示词等相关改造，似乎也没有落地吧？"

**诊断**：Stoa 集成路径其实通了（`ChatView.systemPrompt = ThemeProvider.shared.composedPrompt(base: state.systemPrompt)` 注入；`MarkdownText.shouldUseStoaRenderer = theme.id == .stoa && containsStoaTags` 分发）。但用户感受"没落地"，可能因为：
- 切到 Stoa 后 LLM 没真的吐 `<module>` 等 XML 标签
- 或者 UI 上没看到明显变化

#### `b66f89c fix: Stoa prompt 加 HARD CONSTRAINT`

末尾追加严指令："Your reply MUST start with `<module>`、必含恰一个结构化块、必须以 `</quote>` 结尾、闲聊路由到 M1、显式说"这些标签会被 UI 解析；不输出则用户看到一堵文字墙"作为遵守动机。

#### 用户实测后反馈（4 个具体问题）

> 截图：AI 输出 `<empo energy="?">` 而不是 `<tempo>`；裸 XML 显示在卡片里；reasoning preamble "用户说卡住了..."暴露；预期能在设置中看到 prompt。

`e60fd9a fix: Stoa 4 项整改`：

1. **typo 容错**：StoaParser `tagNames` 从硬编码列表改成 `tagAliases` 字典：
   - `empo → tempo`、`facjudge → factjudge`、`virtus → virtues`、`qoute → quote`、`dichoto → dichotomy`、`rituals → ritual`
   - 匹配后归一化到规范 tag，走原 decode 路径
2. **prompt 收紧**：OUTPUT FORMAT 5 段改 4 段，删 "One short reasoning line"。新增 INTERNAL CHECKLIST（首字 / typo / energy 数值 / 末尾 quote 自检）+ ROUTING FOR EDGE CASES（闲聊 / 多焦点 / 含糊「我卡住了」）+ 完整 EXAMPLE
3. **preamble 兜底**：MessageBubble 加 `stripStoaPreamble()` —— Stoa 主题下 assistant 消息若 `<module>` 不在首位，把它之前的内容自动包成 `<think>...</think>` 让原 ThinkingParser 折叠链路接管 → UI 上 preamble 隐去到「思考」折叠器
4. **设置页可见 prompt**：ThemeSection 新增 `ThemePromptInspector` 折叠模块（默认折叠 → 点击展开显示 monospaced 11pt 文本最高 260pt 可滚 + 复制按钮 + 文末说明）

#### 用户继续实测（3 个细节）

> 截图：右上拉丁问句跟 StatusBar 任务/收件箱角标重叠；卡片可读性差；字体白天黑夜似乎不起作用。

`4f38d0a fix: Stoa 3 项细节`：

1. StoaBackground 拉丁问句从右上挪到左下（先做了一次错误尝试）
2. StoaDichotomyCard / StoaTempoCard 文字颜色从硬编码 hex 改成 `.primary.opacity(0.92)` 跟随主题
3. 验证字体方案路径 —— 路径其实是通的，但实际渲染没生效（埋下伏笔，下一 commit 才找出真凶）

#### 再实测（拉丁问句又跟聊天气泡冲突）

> "聊天气泡下面那个文字突兀，可以去掉。另外 Stoa 模式下深色模式可读性极差。"

`8448adc fix: 删 Stoa 拉丁问句 + 气泡背景动态适配明暗模式`：

1. **直接删** StoaBackground 的拉丁问句 VStack（试过右上、左下都冲突，保留底色 + 横贯分界线 + 朱砂笔印三层就够 Stoa 调性）
2. **气泡背景动态适配明暗**：根因是 `bubbleAssistantStyle` 写死米白色（Stoa）/ 白色半透（Aurora），**深色模式下浅色卡片配 .primary 白字 = 看不清**。改用 `NSColor.dynamicProvider`：
   - Stoa light：米白 0.62 / dark：深米 #2A2620 0.85
   - Aurora light：white 0.42 / dark：black 0.75
3. Theme 文件加 `import AppKit` 以使用 NSColor

#### 用户：「字体切了还是没变」`2de071e fix: 字体方案切换不生效的真凶`

**这是本日最隐蔽的 bug**。

诊断：MarkdownText.inlineMarkdown 用 `Text(AttributedString)` 渲染段落。**AttributedString 在 markdown 解析后每个 character 自带 font attribute（默认 system .body），优先级高于外层 `.font(...)` modifier** → MessageBubble 外层 `.font(fontStyle.bodyFont)` 被完全屏蔽。

修复：MarkdownText 加 `@Environment(\.fontStyle)`，新增 `applyFontStylePreservingEmphasis(_:)` —— 遍历 `attributed.runs`，按 `inlinePresentationIntent` 区分 strong / emphasized / code / regular 四种 run，分别套用 `strongFont / bodyFont.italic() / monoFont / bodyFont`。

副作用：markdown 加粗 / 斜体仍正确，**而且会跟字体方案对齐**（衬线方案下 bold 是 New York Semibold，不再是 SF Pro Bold）。

#### 用户问 Energy bar `2d147bf fix: 删除 Energy bar`

> "Energy Low 的百分比组件是干嘛用的？是真实有效的吗？是系统当前的判断吗？"

**诚实回答**：不是，是 LLM 主观估算（同一句话发两次可能给不同值，没接任何客观信号源）。用户选「干脆删」。

实施：
- StoaTempoCard.body 删除 Energy bar 整段（标题 + Capsule 进度条 + LOW/MID/HIGH 描述 + 分隔线），保留 3 个 optionRow + recommended 标记
- `energyPct` 字段保留（兼容历史消息），仅不再渲染
- prompt M4 schema `<tempo energy="32">` 改成 `<tempo>` + 显式注释「Do NOT add energy="X" attribute」
- INTERNAL CHECKLIST、EXAMPLE、ROUTING EDGE CASES 段同步更新

---

## 3. 关键设计决策与取舍

值得未来翻看的几条决策：

### 3.1 5 AppTab → 3 胶囊的折叠映射

**选项 A**（被否决）：删除 `.tasks` / `.inbox` enum case，把任务和收件箱完全折叠到 chat。问题：会引爆 AppDelegate / PopoverView / openInbox 等多处调用。
**选项 B**（采用）：保留 5 case 不动，MainTabView 内部用 `@State visibleTab` 只在 chat/history/settings 三态间切换，双向 sync state.selectedTab。任务/收件箱降级为 chat tab 上的 popover。
**代价**：胶囊只有 3 颗的"用户视图"和 5 case 的"代码视图"有一层心智落差，写未来代码时容易忘记 visibleTab 是个独立维度。但比改 enum 安全得多。

### 3.2 Hotkey 修复策略：先诊断、后修复

**反例**：第一反应是加 NSEvent global monitor fallback（要"输入监控"权限）。但**没有真凭实据证明 Carbon 链路坏在哪里**就上 fallback，会沉默掩盖真因。
**实采策略**：用 6s self-check + 完整链路 dlog 让用户复现一次就能精确定位 → 用户操作了一次，日志立刻揭示「callback 12 分钟后突然开始 fire」→ 根因坐实 Secure Input mode。
**收益**：避免了"加 fallback 但根因没解决"的工程债。最终的修复（HotkeyHealthMonitor + Banner）是基于诊断结果做的，每行代码都有据可依。

### 3.3 字体系统与主题系统正交

字体方案不绑定主题 —— Aurora 主题可以配「衬线古典」字体（虽然不推荐），Stoa 主题也可以配「圆润现代」（虽然别扭）。`FontStyleID.recommendedFor: [ThemeID]` 仅作"推荐"角标提示。
**理由**：可读性是用户偏好的独立维度，不该被主题美学绑架。

### 3.4 Energy bar 删除而非接入真信号

可选路径：接入 OPC 自有指标（最近 1h 输入字数 / TimerService 中断次数 / activeTask 状态）算真 energy。
**决策**：删。理由：
- 真信号也需要权重设计 + 经验调参，初版可能比 AI 估算更不准
- "镜子，不是仆人"的 Stoa 哲学下，**保留 recommended 这个轻量信号就够了**
- 假信号穿真信号衣服比"没这个组件"更糟

---

## 4. 弯路 / 教训（最有复盘价值）

### 4.1 stash 误诊（阶段 A 开场）

**事件**：我看 `git stash show --name-status stash@{0}` 没看到 Theme 文件，断定 untracked 文件丢了，让用户从 bold-germain 手动复制。**实际上 `--include-untracked` 标志没加**，文件其实完整保留在 `stash@{0}^3` 里。
**根因**：对 `git stash` 的细节不够熟，没意识到默认输出隐藏 untracked。
**教训**：分析 stash 之前先 `git stash show --include-untracked --name-status` 一次性看全。
**代价**：约 5 分钟绕路，多了几条 file copy 命令。无实际损失。

### 4.2 主面板尺寸忘记同步（阶段 B 后果）

**事件**：Agent A 实现三胶囊导航时，没同步把 ContentView frame 从 520 调大。用户截图发现胶囊和输入框对称被裁。
**根因**：Agent A 的 prompt 没显式提醒"加新顶部组件可能需要扩面板"。
**教训**：未来 prompt 派 agent 做 UI 重构时，**显式列出"可能需要联动调整的依赖项"**（panel size、StatusBar 高度、ContentView clipShape 圆角等）。

### 4.3 AttributedString 屏蔽外层 .font（阶段 E 最后）

**事件**：用户反复说"字体没生效"，我第一反应是 environment 传播问题。实际是 `Text(AttributedString)` 内部 font attribute 优先级高于 view modifier。
**根因**：SwiftUI 的 `.font()` modifier 跟 AttributedString.font attribute 的优先级关系不直观（直觉认为外层 modifier 覆盖一切）。
**教训**：用 AttributedString 渲染 Text 时，**字体必须在 AttributedString 自身设置**，不能依赖外层 modifier 传递。

### 4.4 两次右上角 / 左下角拉丁问句的折腾（阶段 E 中段）

**事件**：StoaBackground 右上角的 "Quid hodie tibi imperat?" 跟 StatusBar 任务/收件箱角标冲突 → 我挪到左下角 → 又跟聊天气泡下方时间戳冲突 → 用户「删了吧」。
**根因**：装饰元素的位置在静态设计稿上看着美，叠加动态 UI（StatusBar 角标、聊天历史滚动）就抢空间。
**教训**：纯装饰元素先**问一句"用户场景下它处在什么位置"**再决定保留与否。`StoaBackground` 已经有底色 + 分界线 + 朱砂笔印三层，再加拉丁问句是堆料而非升华。

### 4.5 LLM 输出 XML 标签不可靠

**事件**：Stoa 的 5 模块卡片渲染依赖 LLM 输出 `<tempo>` `<dichotomy>` 等 strict XML。M2-her 模型偶尔会拼错 `empo`、加上多余 reasoning preamble、不填 energy 属性、自创编号 "2. Socratic question" 等。
**教训**：
- Prompt 单层指令不够，要加 INTERNAL CHECKLIST + 完整 EXAMPLE
- 解析器要带 typo 容错（`tagAliases` 字典模式）
- UI 要有 fallback（StoaParser 解析失败回退为 .text 不崩）
- 适当时候考虑微调或多模型对比 —— 但当前规模不值得，先用 prompt 工程压

---

## 5. 技术债 + 已知遗留

### 沿用 EVAL_2026-05-27.md 已识别的 7 条（仍 valid）

| # | 优先级 | 标题 |
|---|---|---|
| 1 | 高 | `AppDelegate.swift` 1000+ 行，该拆了（MenuBarController / PanelController / HotkeyController / ScheduledTaskRunner） |
| 2 | 高 | `ChatView.swift` 1200+ 行（输入框、消息流、Slash、Voice、Notion 卡片渲染都挤在一个文件） |
| 3 | 中 | `StoaParser` 282 行**无单测** |
| 4 | 中 | `forwardStandardEditCommands` 不在 `@MainActor`（Swift 6 warning） |
| 5 | 中 | `ContentView.playEntrance` 用 DispatchQueue.main.asyncAfter，快速 toggle 时动画可能重叠 |
| 6 | 低 | MainTabView 9 条链式 `.animation(_, value:)` 是 SwiftUI 反模式 |
| 7 | 低 | 主题切换没 onAppear 重放入场动画（burst flash 不重现） |

### 本日新增

| # | 优先级 | 标题 |
|---|---|---|
| 8 | 中 | `HotkeyHealthMonitor` 只在启动后 36s 监测，**白天用着用着突然不行了**不会再 banner（已写入 EVAL §5 段 3） |
| 9 | 低 | `PanelWatermark` 已删，但 `panelCornerRadius` 同步逻辑在 ContentView 里耦合了 AppDelegate.shared.panelEffectView —— 跨层引用，可以抽进 ThemeProvider |
| 10 | 低 | Stoa typo 容错只覆盖已知拼写错（empo / facjudge 等），未来 LLM 发明新 typo 仍会失效。考虑改 fuzzy match（Levenshtein 距离 ≤ 2） |
| 11 | 中 | Stoa M5 (Virtues) / M3 (Ritual) 的卡片可能也有"假信号"嫌疑，类似 Energy bar，需要审视一遍 |

---

## 6. 元方法（这一轮试出来的工作模式）

### 6.1 Agent 派遣的有效场景

- **可拆分、互不阻塞的并行任务** → worktree 隔离 agent 适合：阶段 B 同时跑 UI 重构 + 热键修复
- **大批量探索** → Explore agent 适合：调研字体 / 主题相关代码
- **顺序性强的反馈循环** → inline 自己做更快：所有视觉 polish 都是「截图反馈 → 我看 → 改 → 验证」的小步循环，没法分发

### 6.2 Bug 投诉的拆解模板

用户「X 不工作」基本可以套这个三段诊断：
1. **路径活着吗** —— grep 代码确认调用链完整
2. **路径上的某节点行为正确吗** —— dlog / 日志
3. **节点行为正确但效果不对** —— 优先级 / 屏蔽 / 隐式 environment 覆盖

阶段 E 的"字体没生效"恰好是第 3 类，前两次我误判为第 1 / 2 类才绕了一圈。

### 6.3 截图标注红框的反馈方式

用户截图标红框定位问题极其高效（视觉问题用语言描述需要 3-5 句话，红框 1 个）。阶段 D / E 全程都靠用户截图驱动。

---

## 7. 附录：commit 索引

```
2d147bf  fix: 删除 Stoa M4 tempo 卡片的 Energy bar
2de071e  fix: 字体方案切换不生效的真凶 (AttributedString)
8448adc  fix: 删 Stoa 拉丁问句 + 气泡背景动态明暗
4f38d0a  fix: Stoa 3 项细节修复
e60fd9a  fix: Stoa 4 项整改 (typo / prompt / preamble / 设置页可见)
b66f89c  fix: Stoa prompt HARD CONSTRAINT
832f0e4  feat: 颜色方案 + 字体方案系统 (4 套字体 + dark mode)
cdc4ce8  fix: 6 项视觉 polish (圆角/气泡/排版/过渡/热区)
9db2f91  feat: 补齐设计原意 (liquidIn + spring + 主题发送按钮 + InputKeyHint)
3d3f32a  fix: 主面板 520→620
541164d  chore: 调查日志收尾 + 评估报告
ec79a1d  feat: Secure Input 监测 + 热键 Banner + 设置页诊断
3859aec  fix: 全局热键失效诊断
b3e9cad  feat: 主界面三胶囊导航 + 输入框多行扩展
495e8c6  fix: 修复 SecureField 在 HUDPanel 中无法粘贴
56f4b32  feat: 接入 Aurora / Stoa 主题系统 + 入场动效 + build 护栏
─────────────────────────────────────────────
96388d4  feat: 我想功能 + 主动介入引擎 + 记忆跨天 + 状态条常驻 + 闭环加固 (本轮起点)
```

## 8. 配套文件清单

| 文件 | 用途 |
|---|---|
| `ITERATION_2026-05-27.md` | **本文** —— 全程推进文档 |
| `EVAL_2026-05-27.md` | Agent C 中段评估（commit 541164d 时落地） |
| `.bug-investigations/2026-05-27-hotkey-failure.md` | 顽固 bug 调查日志（已标记为「已解决（缓解）」） |
| `Sources/OPCCompanion/Theme/` | 主题系统模块（8 文件） |
| `Sources/OPCCompanion/Theme/FontStyle.swift` | 字体方案系统 |
| `Sources/OPCCompanion/Utils/HotkeyHealthMonitor.swift` | 热键健康监测器 |

---

> 最后 push 状态：本地 = `origin/feature/focused-conversation-memory` = `2d147bf`，**完全同步**。未 merge 到 main（feature 分支即事实主线）。
