# Stoa 思考过程泄漏
创建时间: 2026-05-28
状态: 已解决

## 症状
Stoa 模式下，assistant 回复中的 `<think>...</think>` 思考过程仍会在 UI 中出现。截图显示内部路由分析、输出格式说明以及 `<module>` / `<tempo>` / `<quote>` 等标签被渲染成红色结构化内容。

## 数据流路径
用户输入 -> ChatEngine.sendMessage -> 模型返回包含 `<think>...</think>` 的文本 -> AppState 持久化到 `~/.opc-companion/conversations/2026-05-28.jsonl` -> ChatView.MessageBubble 调用 ThinkingParser -> ThinkingDisclosure 展开后调用 MarkdownText -> StoaRenderer 识别 thinking 内部的 `<module>` / `<tempo>` 片段并结构化渲染。

## 已排除的假设
- [x] 运行了错误 bundle: `ps aux` 确认当前只运行 `/Users/shiye/Projects/OPC 伴侣/OPCCompanion.app/Contents/MacOS/OPCCompanion`。
- [x] 截图来自历史旧消息而非当前返回: `2026-05-28.jsonl` 中存在同一条用户输入和包含 `<think>...</think>` 的 assistant 原文。

## 当前假设
尝试 1 的方向仍然不完整：`MessageBubble` 先执行 `stripStoaPreamble(message.content)`，再交给 `ThinkingParser.parse`。当 thinking 内容里出现 “Start with `<module>` tag” 这样的格式说明时，`stripStoaPreamble` 会在 thinking 内部的 `<module>` 处切开文本，破坏完整 `<think>...</think>` 结构，导致后半段 thinking 进入正文并被 StoaRenderer 渲染。

## 修复尝试记录
### 尝试 1 (当前会话, 2026-05-28)
- 方案: Stoa 模式下隐藏 ThinkingDisclosure；ThinkingParser 同时增强为大小写不敏感、支持属性和 JSON 残留 `<\/think>` 的剥离。
- 结果: `swift test` 84/84 通过；`./build.sh` 成功；已重启主工作区 bundle。
- 结论: 真正根因是 Stoa 模式下仍允许用户展开模型 thinking，并且 thinking 内容会再次进入 MarkdownText/StoaRenderer。修复后 Stoa 不再展示 thinking，正文解析仍保留结构化卡片。

### 尝试 2 (当前会话, 2026-05-28)
- 方案: 调整展示层处理顺序，先用 ThinkingParser 剥离完整 thinking，再只对 parsed.main 做 Stoa preamble 清理；补充覆盖真实复发样本的测试。
- 结果: 新增 `testStoaDisplayParserDoesNotSplitOnModuleMentionInsideThinking` 覆盖真实复发样本；`swift test --filter ThinkingParserTests` 5/5 通过；`swift test` 85/85 通过；`./build.sh` 成功；已重启主工作区 bundle。
- 结论: 真正根因是 Stoa preamble 清理发生在 ThinkingParser 之前，且会命中 thinking 内部的 `<module>` 示例文本。修复后处理顺序固定为先剥 thinking，再清理正文。
