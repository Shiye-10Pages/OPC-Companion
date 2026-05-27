import SwiftUI

struct ChatView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var notionConfirm = NotionConfirmManager.shared
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var isNearBottom = true  // 底部 sentinel 是否在视窗里

    private static let bottomAnchorId = "__chat_bottom_anchor__"

    /// 渲染用消息列表：过滤掉 hidden + 空 assistant 占位（首 token 到达前不显示空气泡，由 TypingIndicator 承接等待态）
    private var renderedMessages: [Message] {
        state.messages.filter { msg in
            guard !msg.hidden else { return false }
            if msg.role == .assistant && msg.content.isEmpty { return false }
            return true
        }
    }

    /// 把 `/命令` 映射到对应 popover Tab（砍-C：设置不再占 StatusBar 图标，靠命令召唤）
    /// 斜杠命令识别（仅保留 3 个：随手记由默认 fallback 处理，今日必做 + 学习走这里）
    static func handleCommand(_ keyword: String, state: AppState) -> Bool {
        switch keyword {
        case "今日必做", "ritual":
            state.showMorningRitual = true; return true
        case "学习", "learn", "dreaming":
            state.triggerDreamingIfNeeded(); return true
        default:
            return false
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // 任务区已迁移到顶部 status bar 的「任务」popover；消息流保持纯净
                // 对话消息区
                ScrollViewReader { proxy in
                    ZStack(alignment: .bottom) {
                        ScrollView {
                            if renderedMessages.isEmpty && !state.isLoading {
                                chatEmptyState
                            } else {
                                LazyVStack(spacing: 12) {
                                    ForEach(renderedMessages) { message in
                                        MessageBubble(message: message)
                                            .id(message.id)
                                            .transition(.liquidIn)   // F. 液态凝结入场
                                    }

                                    if state.isLoading {
                                        TypingIndicator()
                                            .transition(.liquidIn)
                                    }

                                    // 底部 sentinel：出现在视窗时 isNearBottom = true
                                    Color.clear
                                        .frame(height: 1)
                                        .id(Self.bottomAnchorId)
                                        .onAppear { isNearBottom = true }
                                        .onDisappear { isNearBottom = false }
                                }
                                .animation(.spring(response: 0.5, dampingFraction: 0.78), value: renderedMessages.count)
                                .animation(.easeOut(duration: 0.35), value: state.isLoading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                        }
                        .scrollIndicators(.automatic)
                        .onChange(of: state.messages.count) { _, _ in
                            // 新消息进入 → 动画滚动到底
                            if isNearBottom {
                                withAnimation {
                                    proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: state.messages.last?.content ?? "") { _, _ in
                            // 流式 delta 会不断追加最后一条消息的 content（count 不变），这里补跟随
                            if isNearBottom {
                                proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                            }
                        }

                        // 滚动到最新浮层按钮：用户不在底部时显示
                        if !isNearBottom && !renderedMessages.isEmpty {
                            Button {
                                withAnimation(AppAnimations.quick) {
                                    proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("最新")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor)
                                )
                                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 10)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .animation(AppAnimations.quick, value: isNearBottom)
                }

                Divider()

                // 输入区
                InputBar(text: $inputText, isLoading: state.isLoading, isFocused: $isInputFocused) {
                    sendMessage()
                }
            }
            .overlay {
                if notionConfirm.showConfirmation, let toolCall = notionConfirm.pendingToolCall {
                    ZStack {
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                            .onTapGesture { notionConfirm.cancel() }
                        NotionConfirmCard(toolCall: toolCall) {
                            notionConfirm.confirm()
                        } onCancel: {
                            notionConfirm.cancel()
                        }
                        .padding(.horizontal, 32)
                    }
                    .transition(.opacity)
                }
            }
            .animation(AppAnimations.quick, value: notionConfirm.showConfirmation)
            .onAppear {
                focusInputSoon()
            }
            .onChange(of: state.isPanelVisible) { _, isVisible in
                if isVisible {
                    focusInputSoon()
                }
            }
        }
    }

    @ViewBuilder
    private var chatEmptyState: some View {
        if CredentialCache.shared.getMinimaxAPIKey().isEmpty {
            onboardingNotConfigured
        } else {
            welcomeTips
        }
    }

    private var onboardingNotConfigured: some View {
        VStack(spacing: 14) {
            Image(systemName: "key.fill")
                .font(.system(size: 36))
                .foregroundColor(.orange)
            Text("先去设置填 API Key")
                .font(.headline)
            VStack(spacing: 4) {
                Text("OPC 伴侣需要 MiniMax API Key 才能对话")
                Text("可选填 Notion Token 使用 Notion 功能")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)

            Button {
                state.selectedTab = .settings
            } label: {
                Label("打开设置", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var welcomeTips: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("和 OPC 伴侣聊聊")
                .font(.headline)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("· 输入消息按回车发送")
                Text("· 「开始 XX 25 分钟」直接启动计时")
                Text("· 「/ 想法」存为随手记不打扰对话")
                Text("· 长按 Option+Space 进入语音模式")
                Text("· Option+` 快速记一下")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func sendMessage() {
        // 防止并发发送
        guard !state.isLoading else { return }
        let rawInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawInput.isEmpty else { return }

        let inputMode: InputMode = VoiceService.shared.isRecording ? .voice : .text
        if inputMode == .voice {
            VoiceService.shared.stopRecording()
        }

        // `/` 前缀：先看是不是 /聊聊（发给 AI）；再试命令（打开 popover），否则当随手记
        if rawInput.hasPrefix("/") {
            let body = String(rawInput.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            let isWishChat = body == "聊聊" || body.hasPrefix("聊聊 ") || body.hasPrefix("聊聊\t")

            if isWishChat {
                // 启动 wish clearing session（已存在则不重置），然后 fall through 到 AI 路径发送原始消息
                if state.wishClearingSession == nil {
                    let anchor = state.activeTask?.title ?? state.tasks.first(where: { $0.status == .pending })?.title
                    state.startWishClearingSession(anchorTask: anchor)
                }
                // 不 return，继续走下方 AI 发送路径
            } else {
                inputText = ""
                focusInputSoon()
                guard !body.isEmpty else { return }

                // 命令识别：单关键字（中英文均可）
                let lower = body.lowercased()
                if Self.handleCommand(lower, state: state) {
                    return
                }

                // 非命令 → 落到随手记
                state.captureNote(content: body, source: .slashInPanel, inputMode: inputMode)
                state.showBanner("已存随手记", kind: .success)
                MemoryService.shared.appendToToday(.notes, entry: body)
                return
            }
        }

        let userMessage = inputText
        inputText = ""
        focusInputSoon()

        // 添加用户消息
        state.appendMessage(Message(role: .user, content: userMessage, inputMode: inputMode))

        // 本地预解析：用户明确「开始 XX N 分钟」→ 直接启动计时（不等 AI 返回）
        if let timer = ChatEngine.detectLocalTimer(in: userMessage) {
            state.startTimer(task: timer.task, minutes: timer.minutes)
        }

        // 插入空 assistant 占位，流式把增量拼接进去
        let placeholder = Message(role: .assistant, content: "", inputMode: inputMode)
        state.appendMessage(placeholder)
        let msgID = placeholder.id

        // C1：guard 后**立即同步**设 true，避免与后续 Task 调度之间的并发窗口
        state.isLoading = true

        Task { @MainActor in
            // defer 兜底：无论 success / throw / cancel 都正确归位 isLoading + 持久化
            // 若 /聊聊 路径异常，这里也会把 wish session 清掉，防止 session 残留污染后续对话
            defer {
                state.persistMessage(id: msgID)
                state.isLoading = false
                focusInputSoon()
            }

            do {
                let systemPrompt = ThemeProvider.shared.composedPrompt(base: state.systemPrompt)
                let response = try await ChatEngine.shared.sendMessage(
                    userMessage,
                    systemPrompt: systemPrompt,
                    onAssistantDelta: { delta in
                        Task { @MainActor in
                            if let idx = AppState.shared.messages.firstIndex(where: { $0.id == msgID }) {
                                AppState.shared.messages[idx].content += delta
                            }
                        }
                    }
                )

                // M7：取流式累积 vs response 里更长的那个，避免多轮 tool 调用时被覆盖丢前几轮
                if let idx = state.messages.firstIndex(where: { $0.id == msgID }),
                   state.messages[idx].content.count < response.count {
                    state.messages[idx].content = response
                }

                // 语音输入模式：朗读回复
                if inputMode == .voice {
                    TTSService.shared.speak(response, voiceId: state.config.voice.ttsVoice, rate: state.config.voice.ttsRate)
                }
            } catch {
                if let idx = state.messages.firstIndex(where: { $0.id == msgID }) {
                    let partial = state.messages[idx].content
                    if !partial.isEmpty {
                        // 已收到部分内容 → 保留 + 追加断开标记
                        state.messages[idx].content = partial + "\n\n— [连接中断: \(error.localizedDescription)]"
                    } else {
                        // 完全没收到 → assistant 气泡替换为友好错误提示（保持 role 不变，消息流只有 user/assistant）
                        state.messages[idx].content = "抱歉，出了点问题：\(error.localizedDescription)"
                    }
                }
                state.showBanner("消息发送失败：\(error.localizedDescription)", kind: .error, duration: 5.0)
                // Batch 1.6：/聊聊 catch 分支同步回滚 wish session，避免残留污染后续对话
                if rawInput.hasPrefix("/") {
                    let body = String(rawInput.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                    if body == "聊聊" || body.hasPrefix("聊聊 ") || body.hasPrefix("聊聊\t") {
                        state.endWishClearingSession()
                    }
                }
            }
        }
    }

    private func focusInputSoon() {
        DispatchQueue.main.async {
            isInputFocused = true
        }
    }
}

struct TaskSection: View {
    @EnvironmentObject var state: AppState
    @State private var isExpanded = true

    var body: some View {
        Group {
            if state.tasks.isEmpty {
                compactEmptyBar
            } else {
                fullSection
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var compactEmptyBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "checklist")
                .font(.system(size: 12))
            Text("今日任务 · 暂无")
                .font(.caption)
            Spacer()
            Button { state.showAddTaskOverlay = true } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help("添加任务")
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.button)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        )
    }

    private var fullSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checklist")
                    .font(.system(size: 14, weight: .medium))
                Text("今日任务")
                    .font(AppTypography.body.bold())

                Spacer()

                Text("\(state.tasks.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppColors.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(AppColors.primary.opacity(0.18))
                    .cornerRadius(10)

                Button { state.showAddTaskOverlay = true } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .help("添加任务")

                Button {
                    withAnimation(AppAnimations.quick) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(state.tasks) { task in
                        TaskCard(task: task)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.card)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
    }

}

struct AddTaskSheet: View {
    @State private var title = ""
    @State private var minutes = 25
    @State private var hasTimer = true
    @State private var pomodoroCycle = false
    @State private var focusMode = false
    let onSave: (String, Int?, Bool, Bool) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("添加任务")
                .font(.headline)

            TextField("任务名称", text: $title)
                .textFieldStyle(.roundedBorder)

            Toggle("启动计时", isOn: $hasTimer)

            if hasTimer {
                HStack(spacing: 8) {
                    Text("时长")
                    Spacer()
                    TextField("25", value: $minutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: minutes) { _, newValue in
                            if newValue < 1 { minutes = 1 }
                            else if newValue > 240 { minutes = 240 }
                        }
                    Text("分钟")
                    Stepper("", value: $minutes, in: 1...240, step: 5)
                        .labelsHidden()
                }

                Toggle(isOn: $pomodoroCycle) {
                    HStack(spacing: 6) {
                        Text("🍅")
                        Text("Pomodoro 循环（自动 25+5 切换）")
                            .font(.system(size: 12))
                    }
                }
                Toggle(isOn: $focusMode) {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.fill")
                        Text("深度专注（切换 macOS 勿扰）")
                            .font(.system(size: 12))
                    }
                }
            }

            HStack {
                Button("取消") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    onSave(
                        title.trimmingCharacters(in: .whitespacesAndNewlines),
                        hasTimer ? minutes : nil,
                        pomodoroCycle && hasTimer,
                        focusMode && hasTimer
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .glassBackground()
    }
}

struct TaskCard: View {
    let task: TaskItem
    @EnvironmentObject var state: AppState

    private var statusColor: Color {
        switch task.status {
        case .pending: return AppColors.taskPending
        case .inProgress: return AppColors.taskInProgress
        case .done: return AppColors.taskDone
        case .cancelled: return AppColors.taskCancelled
        }
    }

    private var isActive: Bool { task.status == .inProgress }

    var body: some View {
        HStack(spacing: 10) {
            // 状态指示器
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(statusColor.opacity(0.3), lineWidth: 2)
                )

            // 任务信息
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: isActive ? 14 : 13, weight: isActive ? .semibold : .regular))
                    .strikethrough(task.status == .done)
                    .foregroundColor(task.status == .done ? .secondary : .primary)

                if isActive, let remaining = task.remainingSeconds {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text(formatTime(remaining))
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .foregroundColor(remaining < 300 ? AppColors.statusError : .secondary)
                }
            }

            Spacer()

            actionButtons

            // 状态标签
            statusTag
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.button)
                .fill(isActive ? AppColors.taskInProgress.opacity(0.10) : AppColors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.button)
                .stroke(isActive ? AppColors.taskInProgress.opacity(0.35) : AppColors.cardBorder, lineWidth: isActive ? 1.5 : 1)
        )
        .overlay(alignment: .leading) {
            // 进行中任务左侧 3px 彩条，让"眼下该做什么"一眼可见
            if isActive {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.taskInProgress)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch task.status {
        case .inProgress:
            HStack(spacing: 2) {
                HoverIconButton(systemImage: "checkmark.circle", help: "完成任务") { complete() }
                HoverIconButton(label: "+10m", help: "延长 10 分钟") { extend(10) }
                HoverIconButton(systemImage: "xmark.circle", help: "取消任务") { cancelTask() }
            }
        case .pending:
            HStack(spacing: 2) {
                HoverIconButton(systemImage: "play.circle", help: "开始 25 分钟计时") { startPending() }
                HoverIconButton(systemImage: "xmark.circle", help: "删除任务") { cancelTask() }
            }
        case .done:
            HStack(spacing: 2) {
                HoverIconButton(systemImage: "arrow.uturn.backward.circle", help: "撤销完成") { reopen() }
            }
        case .cancelled:
            HStack(spacing: 2) {
                HoverIconButton(systemImage: "arrow.uturn.backward.circle", help: "恢复为待办") { reopen() }
            }
        }
    }

    private func complete() {
        guard let idx = state.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        state.tasks[idx].actualMinutes = AppState.actualMinutes(for: state.tasks[idx])
        state.tasks[idx].status = .done
        let wasActive = state.activeTask?.id == task.id
        if wasActive {
            state.activeTask = nil
            state.menuBarStatus = .idle
            state.resetTimerFlags()
        }
        state.saveTasks()
        state.showBanner("已完成：\(task.title)", kind: .success)
        let note = AppState.estimateVsActualNote(for: state.tasks[idx])
        MemoryService.shared.appendToToday(.tasks, entry: "完成：\(task.title)\(note)")
        state.enqueuePostMortem(state.tasks[idx])
        state.refreshNextCandidates(excluding: task.id)
        // T3-12 关闭 Focus mode
        if state.tasks[idx].focusMode {
            Task { await FocusModeService.shared.disable() }
        }
    }

    private func cancelTask() {
        guard let idx = state.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        state.tasks[idx].status = .cancelled
        let wasActive = state.activeTask?.id == task.id
        if wasActive {
            state.activeTask = nil
            state.menuBarStatus = .idle
            state.resetTimerFlags()
        }
        state.saveTasks()
        state.enqueuePostMortem(state.tasks[idx])
        if state.tasks[idx].focusMode {
            Task { await FocusModeService.shared.disable() }
        }
    }

    private func extend(_ minutes: Int) {
        guard let idx = state.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let base = state.tasks[idx].timerEnd ?? Date()
        state.tasks[idx].timerEnd = base.addingTimeInterval(TimeInterval(minutes * 60))
        state.tasks[idx].extensions += 1
        if state.activeTask?.id == task.id {
            state.activeTask = state.tasks[idx]
            state.menuBarStatus = .focus
            state.resetTimerFlags()
        }
        state.saveTasks()
        state.showBanner("已延长 \(minutes) 分钟", kind: .info)
        MemoryService.shared.appendToToday(.tasks, entry: "延长 \(minutes) 分钟：\(task.title)")
    }

    private func startPending() {
        guard let idx = state.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let minutes = 25
        state.tasks[idx].status = .inProgress
        state.tasks[idx].timerMinutes = minutes
        state.tasks[idx].timerStart = Date()
        state.tasks[idx].timerEnd = Date().addingTimeInterval(TimeInterval(minutes * 60))
        state.activeTask = state.tasks[idx]
        state.menuBarStatus = .focus
        state.resetTimerFlags()
        state.saveTasks()
        state.showBanner("已启动计时：\(task.title) · \(minutes) 分钟", kind: .success)
        MemoryService.shared.appendToToday(.tasks, entry: "启动计时：\(task.title) · \(minutes) 分钟")
    }

    /// 从 done / cancelled 撤销回 pending
    private func reopen() {
        guard let idx = state.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        state.tasks[idx].status = .pending
        state.tasks[idx].timerStart = nil
        state.tasks[idx].timerEnd = nil
        state.saveTasks()
        state.showBanner("已撤销：\(task.title)", kind: .info)
        MemoryService.shared.appendToToday(.tasks, entry: "撤销：\(task.title)")
    }

    @ViewBuilder
    private var statusTag: some View {
        switch task.status {
        case .pending:
            Text("待办")
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.3))
                .foregroundColor(Color(nsColor: .labelColor))
                .cornerRadius(6)
        case .inProgress:
            HStack(spacing: 4) {
                Circle()
                    .fill(AppColors.taskInProgress)
                    .frame(width: 6, height: 6)
                Text("进行中")
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.3))
            .foregroundColor(.green)
            .cornerRadius(6)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.green)
        case .cancelled:
            Text("已取消")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.red)
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

struct MessageBubble: View {
    let message: Message
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme
    @Environment(\.fontStyle) private var fontStyle
    @State private var hovering = false

    private var isUser: Bool {
        message.role == .user
    }

    private var convertible: Bool {
        message.role != .system &&
        Date().timeIntervalSince(message.timestamp) < 24 * 3600
    }

    /// 流式阶段 `<think>` 未闭合时为 true
    private var isMidStreamThinking: Bool {
        message.content.contains("<think>") && !message.content.contains("</think>")
    }

    var body: some View {
        let parsed = ThinkingParser.parse(message.content)

        HStack(alignment: .top, spacing: 6) {
            if isUser { Spacer(minLength: 40) }

            if isUser { captureIconButton }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if isMidStreamThinking {
                    // 流式思考中：只显示占位灰字，不暴露原始 <think> 内容
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("思考中...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let thinking = parsed.thinking {
                    ThinkingDisclosure(text: thinking)
                }

                // 气泡正文：思考中跳过，thinking-only 跳过，有 main 才渲染
                if let displayText = bubbleDisplayText(parsed: parsed), !displayText.isEmpty {
                    MarkdownText(text: displayText)
                    .font(fontStyle.bodyFont)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(isUser ? .white : theme.textPrimary)
                    .background(
                        RoundedRectangle(cornerRadius: theme.bubbleCornerRadius, style: .continuous)
                            .fill(isUser ? theme.bubbleUserStyle : theme.bubbleAssistantStyle)
                    )
                    // AI 气泡极淡内描边，强化与 panel 的层次（不开给用户气泡，那已有 edge glow）
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.bubbleCornerRadius, style: .continuous)
                            .stroke(isUser ? Color.clear : theme.textTertiary.opacity(0.16), lineWidth: 0.5)
                    )
                    .auroraEdgeGlow(
                        active: isUser && theme.id == .aurora,
                        cornerRadius: theme.bubbleCornerRadius
                    )
                    .shadow(color: AppShadows.bubble.color, radius: AppShadows.bubble.radius, x: AppShadows.bubble.x, y: AppShadows.bubble.y)
                }

                HStack(spacing: 6) {
                    if message.inputMode == .voice {
                        Image(systemName: "waveform")
                            .font(.caption)
                    }
                    Text(formatTime(message.timestamp))
                        .font(fontStyle.timestampFont)
                        .foregroundColor(theme.textTertiary)
                }
            }

            if !isUser { captureIconButton }

            if !isUser { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())  // 让整行 HStack 都可以捕获 hover
        .onHover { isHovering in
            // 整行 hover，移动到按钮不会失焦；hide 时小延迟避免在两个子视图之间抖动
            if isHovering {
                withAnimation(AppAnimations.quick) { hovering = true }
            } else {
                withAnimation(AppAnimations.quick) { hovering = false }
            }
        }
    }

    /// 恒定占位图标按钮：opacity 切换而非 show/hide，避免布局抖动导致闪烁
    @ViewBuilder
    private var captureIconButton: some View {
        Button {
            state.convertMessageToNote(message)
        } label: {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Color.secondary.opacity(hovering ? 0.12 : 0))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("转随手记")
        .opacity(hovering && convertible ? 1.0 : 0.0)
        .allowsHitTesting(hovering && convertible)
        .padding(.top, 4)  // 与气泡上缘对齐一点视觉余量
    }

    private struct ThinkingDisclosure: View {
        let text: String
        @State private var isExpanded = false

        /// 折叠态：第一行灰色预览（参考 Claude 思考过程样式）
        private var firstLineSnippet: String {
            let firstLine = text.components(separatedBy: .newlines)
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
                .trimmingCharacters(in: .whitespaces) ?? ""
            if firstLine.count > 64 {
                let idx = firstLine.index(firstLine.startIndex, offsetBy: 64)
                return String(firstLine[..<idx]) + "…"
            }
            return firstLine
        }

        var body: some View {
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        withAnimation(AppAnimations.quick) { isExpanded = false }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.down")
                            Text("思考过程")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    MarkdownText(text: text)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                        )
                }
            } else {
                Button {
                    withAnimation(AppAnimations.quick) { isExpanded = true }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                        Text(firstLineSnippet)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("点击展开思考过程")
            }
        }
    }

    private func bubbleDisplayText(parsed: ThinkingParser.ParsedContent) -> String? {
        if isMidStreamThinking { return nil }
        if parsed.main.isEmpty && parsed.thinking != nil { return nil }
        return parsed.main.isEmpty ? message.content : parsed.main
    }

    private var bubbleBackground: some ShapeStyle {
        switch message.role {
        case .user:
            return theme.bubbleUserStyle
        case .assistant:
            return theme.bubbleAssistantStyle
        case .system:
            return AnyShapeStyle(AppColors.systemBubble)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct TypingIndicator: View {
    @Environment(\.theme) private var theme
    @State private var animating = false

    var body: some View {
        Group {
            if theme.id == .aurora {
                HStack {
                    AuroraShimmerTyping()
                    Spacer()
                }
            } else {
                HStack {
                    HStack(spacing: 5) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(theme.textSecondary)
                                .frame(width: 6, height: 6)
                                .scaleEffect(animating ? 1.2 : 0.8)
                                .animation(
                                    .easeInOut(duration: 0.4)
                                    .repeatForever()
                                    .delay(Double(index) * 0.15),
                                    value: animating
                                )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(theme.bubbleAssistantStyle)
                    .cornerRadius(theme.bubbleCornerRadius)
                    .shadow(color: AppShadows.bubble.color, radius: AppShadows.bubble.radius, x: AppShadows.bubble.x, y: AppShadows.bubble.y)

                    Spacer(minLength: 60)
                }
                .onAppear { animating = true }
            }
        }
        .padding(.horizontal, 12)
    }
}

struct InputBar: View {
    @Binding var text: String
    let isLoading: Bool
    let isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme
    @Environment(\.fontStyle) private var fontStyle
    @ObservedObject private var voice = VoiceService.shared
    @State private var micPulse = false
    @State private var slashSelectedIndex = 0
    /// 选中一条命令后立即收起菜单；删空 "/" 再重新触发会自动恢复。
    @State private var slashMenuCollapsed = false

    private var isNoteMode: Bool {
        text.hasPrefix("/")
    }

    /// `/` 后面的关键词（去掉 `/` 前缀）
    private var slashQuery: String {
        guard text.hasPrefix("/") else { return "" }
        return String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private var slashCommands: [SlashCommand] {
        guard text.hasPrefix("/") else { return [] }
        return SlashCommand.filtered(by: slashQuery)
    }

    private var showSlashMenu: Bool {
        !slashMenuCollapsed && text.hasPrefix("/") && !slashCommands.isEmpty
    }

    private var borderColor: Color {
        if isNoteMode { return .yellow }
        if isFocused.wrappedValue { return theme.accent }
        return .clear
    }

    var body: some View {
        VStack(spacing: 4) {
            // 顶部 hint 条：右下角极简单条 ⏎ SEND，不抢戏
            HStack {
                Spacer()
                InputKeyHint(key: "⏎", label: "SEND")
            }
            .padding(.horizontal, 18)
            .opacity(0.55)

            HStack(spacing: 12) {
            // 输入框容器 + 命令补全菜单
            VStack(spacing: 0) {
                if showSlashMenu {
                    SlashCommandMenuView(
                        commands: slashCommands,
                        selectedIndex: min(slashSelectedIndex, slashCommands.count - 1),
                        onSelect: { executeSlashCommand($0) }
                    )
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                HStack(spacing: 8) {
                    TextField(isNoteMode ? "记一下..." : "发送消息（/ 开头存为随手记）", text: $text, axis: .vertical)
                        .lineLimit(1...6)
                        .textFieldStyle(.plain)
                        .focused(isFocused)
                        .font(fontStyle.bodyFont)
                        .foregroundStyle(theme.textPrimary)
                        .onSubmit {
                            if showSlashMenu {
                                let idx = min(slashSelectedIndex, slashCommands.count - 1)
                                if idx >= 0 && idx < slashCommands.count {
                                    executeSlashCommand(slashCommands[idx])
                                    return
                                }
                            }
                            if !isLoading && !text.isEmpty {
                                onSend()
                            }
                        }
                        // 长按 Option+Space 录音松手后，VoiceService.transcript 更新 → 填入输入框
                        .onChange(of: voice.transcript) { _, newValue in
                            if !voice.isRecording && !newValue.isEmpty {
                                text = newValue
                            }
                        }
                        .onChange(of: text) { _, newValue in
                            slashSelectedIndex = 0
                            // 删空或改成非 "/" 开头 → 允许菜单重新展开
                            if !newValue.hasPrefix("/") {
                                slashMenuCollapsed = false
                            }
                        }
                        .onKeyPress(.upArrow) {
                            guard showSlashMenu else { return .ignored }
                            slashSelectedIndex = max(0, slashSelectedIndex - 1)
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            guard showSlashMenu else { return .ignored }
                            slashSelectedIndex = min(slashCommands.count - 1, slashSelectedIndex + 1)
                            return .handled
                        }
                        .onKeyPress(.escape) {
                            if showSlashMenu { text = ""; return .handled }
                            return .ignored
                        }
                        // axis: .vertical 后回车默认换行，这里拦截：单独回车 = 发送 / 执行命令；
                        // Shift+Enter 让系统插入换行（return .ignored）
                        .onKeyPress(keys: [.return], phases: .down) { press in
                            if press.modifiers.contains(.shift) { return .ignored }
                            if showSlashMenu {
                                let idx = min(slashSelectedIndex, slashCommands.count - 1)
                                if idx >= 0 && idx < slashCommands.count {
                                    executeSlashCommand(slashCommands[idx])
                                    return .handled
                                }
                            }
                            if !isLoading && !text.isEmpty {
                                onSend()
                                return .handled
                            }
                            return .handled
                        }

                if isNoteMode {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.caption)
                        .foregroundColor(.yellow)
                        .padding(.trailing, 4)
                }

                // 语音输入状态指示
                if voice.isRecording {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text("录音中")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(.trailing, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: AppCornerRadius.input)
                    .fill(AppColors.inputBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.input)
                    .stroke(borderColor, lineWidth: 1.5)
            )
            .auroraFocusRings(
                active: isFocused.wrappedValue && theme.id == .aurora,
                cornerRadius: AppCornerRadius.input,
                accent: theme.accent
            )
            .shimmerBorder(
                active: voice.isRecording,
                cornerRadius: AppCornerRadius.input
            )
            .shadow(color: isFocused.wrappedValue ? theme.accent.opacity(0.30) : .clear,
                    radius: 10, x: 0, y: 4)
            .animation(.easeInOut(duration: 0.25), value: isFocused.wrappedValue)
            } // closes VStack(spacing: 0) — 命令补全菜单 + 输入框容器

            // 麦克风按钮（扩大热区到 40×40，按钮本体仍 32 视觉一致）
            Button {
                toggleRecording()
            } label: {
                Image(systemName: voice.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(voice.isRecording ? .red : .secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(voice.isRecording ? .red.opacity(0.1) : Color.clear)
                    )
                    .scaleEffect(micPulse ? 1.15 : 1.0)
                    .animation(
                        micPulse
                            ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                            : .default,
                        value: micPulse
                    )
                    .frame(width: 40, height: 40)        // 外圈热区
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onChange(of: voice.isRecording) { _, isRec in
                withAnimation { micPulse = isRec }
            }

            // 发送按钮（主题渐变圆形 + accent 阴影，接入视觉锤；热区扩到 40×40）
            Button(action: onSend) {
                ZStack {
                    Circle().fill(theme.bubbleUserStyle)
                    if text.isEmpty {
                        Circle().fill(Color.gray.opacity(0.3))
                    }
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(text.isEmpty ? theme.textSecondary : .white)
                }
                .frame(width: 32, height: 32)
                .shadow(color: text.isEmpty ? .clear : theme.accent.opacity(0.35),
                        radius: 8, x: 0, y: 3)
                .frame(width: 40, height: 40)            // 外圈热区
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(text.isEmpty || isLoading)
            } // closes HStack(spacing: 12) — 输入框 + mic + send 主行
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Divider().opacity(0.5), alignment: .top)
        )
        .onAppear {
            isFocused.wrappedValue = true
        }
    }

    private func executeSlashCommand(_ cmd: SlashCommand) {
        let shouldClear = cmd.execute(state)
        if shouldClear {
            text = ""
        } else if let rep = cmd.replacement {
            text = rep
        }
        // 选中即收起菜单。text 回到非 "/" 开头时（比如清空）会在 onChange 里复位。
        slashMenuCollapsed = true
    }

    private func toggleRecording() {
        if voice.isRecording {
            voice.stopRecording()
            if !voice.transcript.isEmpty {
                text = voice.transcript
            } else {
                state.showBanner("未识别到语音，请重试", kind: .info)
            }
        } else {
            Task {
                let authorized = await voice.requestAuthorization()
                if authorized {
                    do {
                        try voice.startRecording()
                    } catch {
                        state.showBanner("语音识别失败：\(error.localizedDescription)", kind: .error, duration: 5.0)
                    }
                } else {
                    state.showBanner("语音识别未授权，请在系统设置 > 隐私与安全性 > 语音识别中开启", kind: .warning, duration: 6.0)
                }
            }
        }
    }
}

// MARK: - 输入条快捷键提示（Linear / Raycast 风 power-user 提示）

struct InputKeyHint: View {
    @Environment(\.theme) private var theme
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 2.5)
                        .stroke(theme.textTertiary, lineWidth: 0.5)
                )
                .foregroundStyle(theme.textSecondary)
            Text(label)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(theme.textTertiary)
        }
    }
}
