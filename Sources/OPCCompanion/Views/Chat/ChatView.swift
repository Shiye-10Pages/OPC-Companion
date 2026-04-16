import SwiftUI

struct ChatView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var notionConfirm = NotionConfirmManager.shared
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // 当日任务区
                TaskSection()

                // 对话消息区
                ScrollViewReader { proxy in
                    ScrollView {
                        if state.messages.filter({ !$0.hidden }).isEmpty && !state.isLoading {
                            chatEmptyState
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(state.messages.filter { !$0.hidden }) { message in
                                    MessageBubble(message: message)
                                        .id(message.id)
                                }

                                if state.isLoading {
                                    TypingIndicator()
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: state.messages.count) { _, _ in
                        if let lastMessage = state.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // 输入区
                InputBar(text: $inputText, isLoading: state.isLoading) {
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
            .animation(.easeInOut(duration: 0.2), value: notionConfirm.showConfirmation)
            .onAppear {
                isInputFocused = true
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

        // `/` 前缀 → 随手记，不走 AI 对话流
        if rawInput.hasPrefix("/") {
            let content = String(rawInput.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            inputText = ""
            isInputFocused = true
            guard !content.isEmpty else { return }
            state.captureNote(content: content, source: .slashInPanel, inputMode: inputMode)
            state.appendMessage(Message(role: .system, content: "📥 已存随手记：\(content)"))
            return
        }

        let userMessage = inputText
        inputText = ""
        isInputFocused = true

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

        Task {
            state.isLoading = true

            do {
                let systemPrompt = state.systemPrompt
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

                // 确保最终内容与返回文本一致（防止最后一帧丢失）
                if let idx = state.messages.firstIndex(where: { $0.id == msgID }),
                   state.messages[idx].content != response {
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
                        // 完全没收到 → 替换为错误提示
                        state.messages[idx].role = .system
                        state.messages[idx].content = "抱歉，出了点问题：\(error.localizedDescription)"
                    }
                }
            }

            state.isLoading = false
        }
    }
}

struct TaskSection: View {
    @EnvironmentObject var state: AppState
    @State private var isExpanded = true
    @State private var showAddTask = false

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
        .sheet(isPresented: $showAddTask) {
            AddTaskSheet { title, minutes in
                addTask(title: title, minutes: minutes)
            }
        }
    }

    private var compactEmptyBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "checklist")
                .font(.system(size: 12))
            Text("今日任务 · 暂无")
                .font(.caption)
            Spacer()
            Button { showAddTask = true } label: {
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

                Button { showAddTask = true } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .help("添加任务")

                Button {
                    withAnimation(AppAnimations.quick) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
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

    private func addTask(title: String, minutes: Int?) {
        let task: TaskItem
        if let m = minutes, m > 0 {
            task = TaskItem(
                title: title,
                status: .inProgress,
                timerMinutes: m,
                timerStart: Date(),
                timerEnd: Date().addingTimeInterval(TimeInterval(m * 60))
            )
            state.activeTask = task
            state.menuBarStatus = .focus
            state.resetTimerFlags()
        } else {
            task = TaskItem(title: title, status: .pending)
        }
        state.tasks.append(task)
        state.saveTasks()
        if let m = minutes, m > 0 {
            state.appendMessage(Message(role: .system, content: "✓ 已启动计时：\(title) · \(m) 分钟"))
        } else {
            state.appendMessage(Message(role: .system, content: "✓ 已添加任务：\(title)"))
        }
    }
}

struct AddTaskSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var minutes = 25
    @State private var hasTimer = true
    let onSave: (String, Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加任务")
                .font(.headline)

            TextField("任务名称", text: $title)
                .textFieldStyle(.roundedBorder)

            Toggle("启动计时", isOn: $hasTimer)

            if hasTimer {
                HStack {
                    Text("时长")
                    Spacer()
                    Stepper(value: $minutes, in: 1...240, step: 5) {
                        Text("\(minutes) 分钟").monospacedDigit()
                    }
                }
            }

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("保存") {
                    onSave(title.trimmingCharacters(in: .whitespacesAndNewlines),
                           hasTimer ? minutes : nil)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
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
                    .font(.system(size: 13))
                    .strikethrough(task.status == .done)
                    .foregroundColor(task.status == .done ? .secondary : .primary)

                if task.status == .inProgress, let remaining = task.remainingSeconds {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(formatTime(remaining))
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .foregroundColor(remaining < 300 ? .red : .secondary)
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
                .fill(AppColors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.button)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch task.status {
        case .inProgress:
            HStack(spacing: 4) {
                Button { complete() } label: {
                    Image(systemName: "checkmark.circle")
                }
                .buttonStyle(.borderless)
                .help("完成任务")

                Button { extend(10) } label: {
                    Text("+10m").font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("延长 10 分钟")

                Button { cancelTask() } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("取消任务")
            }
            .foregroundColor(.secondary)
        case .pending:
            HStack(spacing: 4) {
                Button { startPending() } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .help("开始 25 分钟计时")

                Button { cancelTask() } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("删除任务")
            }
            .foregroundColor(.secondary)
        default:
            EmptyView()
        }
    }

    private func complete() {
        guard let idx = state.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        state.tasks[idx].status = .done
        if state.activeTask?.id == task.id {
            state.activeTask = nil
            state.menuBarStatus = .idle
            state.resetTimerFlags()
        }
        state.saveTasks()
        state.appendMessage(Message(role: .system, content: "✓ 已完成：\(task.title)"))
    }

    private func cancelTask() {
        guard let idx = state.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        state.tasks[idx].status = .cancelled
        if state.activeTask?.id == task.id {
            state.activeTask = nil
            state.menuBarStatus = .idle
            state.resetTimerFlags()
        }
        state.saveTasks()
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
        state.appendMessage(Message(role: .system, content: "✓ 已延长 \(minutes) 分钟"))
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
        state.appendMessage(Message(role: .system, content: "✓ 已启动计时：\(task.title) · \(minutes) 分钟"))
    }

    @ViewBuilder
    private var statusTag: some View {
        switch task.status {
        case .pending:
            Text("待办")
                .font(.system(size: 10, weight: .medium))
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
            .font(.system(size: 10, weight: .medium))
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
                .font(.system(size: 10, weight: .medium))
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
    @State private var hovering = false
    @State private var hoverTask: DispatchWorkItem?
    @State private var showCaptureButton = false

    private var isUser: Bool {
        message.role == .user
    }

    private var convertible: Bool {
        // 仅 24 小时内的 user / assistant 消息可转
        message.role != .system &&
        Date().timeIntervalSince(message.timestamp) < 24 * 3600
    }

    var body: some View {
        let parsed = ThinkingParser.parse(message.content)

        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if let thinking = parsed.thinking {
                    ThinkingDisclosure(text: thinking)
                }

                MarkdownText(text: parsed.main.isEmpty ? message.content : parsed.main)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .cornerRadius(AppCornerRadius.bubble)
                    .shadow(color: AppShadows.bubble.color, radius: AppShadows.bubble.radius, x: AppShadows.bubble.x, y: AppShadows.bubble.y)
                    .overlay(alignment: .top) {
                        if showCaptureButton && convertible {
                            captureButton
                                // 让按钮的"底部"对齐气泡的"顶部"，再向上偏移 6pt。无论按钮高度如何都稳定。
                                .alignmentGuide(.top) { d in d[.bottom] + 6 }
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }

                // 时间戳 + 输入模式图标
                HStack(spacing: 4) {
                    if message.inputMode == .voice {
                        Image(systemName: "waveform")
                            .font(.caption2)
                    }
                    Text(formatTime(message.timestamp))
                        .font(AppTypography.timestamp)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .onHover { isHovering in
                hovering = isHovering
                hoverTask?.cancel()
                if isHovering && convertible {
                    let task = DispatchWorkItem {
                        withAnimation(.easeOut(duration: 0.15)) {
                            showCaptureButton = true
                        }
                    }
                    hoverTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
                } else {
                    withAnimation(.easeIn(duration: 0.1)) {
                        showCaptureButton = false
                    }
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 12)
    }

    private struct ThinkingDisclosure: View {
        let text: String
        @State private var isExpanded = false

        var body: some View {
            DisclosureGroup(isExpanded: $isExpanded) {
                MarkdownText(text: text)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                    )
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                    Text("思考过程")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            }
        }
    }

    private var captureButton: some View {
        Button {
            state.convertMessageToNote(message)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tray.and.arrow.down")
                Text("随手记")
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var bubbleBackground: some ShapeStyle {
        switch message.role {
        case .user:
            return AnyShapeStyle(AppColors.primaryGradient)
        case .assistant:
            return AnyShapeStyle(AppColors.assistantBubble)
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
    @State private var animating = false

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary)
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
            .background(AppColors.assistantBubble)
            .cornerRadius(AppCornerRadius.bubble)
            .shadow(color: AppShadows.bubble.color, radius: AppShadows.bubble.radius, x: AppShadows.bubble.x, y: AppShadows.bubble.y)

            Spacer(minLength: 60)
        }
        .padding(.horizontal, 12)
        .onAppear { animating = true }
    }
}

struct InputBar: View {
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void
    @EnvironmentObject var state: AppState
    @ObservedObject private var voice = VoiceService.shared
    @FocusState private var isFocused: Bool
    @State private var micPulse = false

    private var isNoteMode: Bool {
        text.hasPrefix("/")
    }

    private var borderColor: Color {
        if isNoteMode { return .yellow }
        if isFocused { return AppColors.primary }
        return .clear
    }

    var body: some View {
        HStack(spacing: 12) {
            // 输入框容器
            HStack(spacing: 8) {
                TextField(isNoteMode ? "记一下..." : "发送消息（/ 开头存为随手记）", text: $text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .font(AppTypography.body)
                    .onSubmit {
                        if !isLoading && !text.isEmpty {
                            onSend()
                        }
                    }

                if isNoteMode {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.caption)
                        .foregroundColor(.yellow)
                        .padding(.trailing, 4)
                }

                // 语音输入状态指示
                if VoiceService.shared.isRecording {
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

            // 麦克风按钮
            Button {
                toggleRecording()
            } label: {
                Image(systemName: voice.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(voice.isRecording ? .red : .secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(voice.isRecording ? .red.opacity(0.2) : Color.clear)
                    )
                    .scaleEffect(voice.isRecording && micPulse ? 1.15 : 1.0)
                    .animation(
                        voice.isRecording
                            ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                            : .default,
                        value: micPulse
                    )
            }
            .buttonStyle(.plain)
            .onChange(of: voice.isRecording) { _, isRec in
                micPulse = isRec
            }

            // 发送按钮
            Button(action: onSend) {
                ZStack {
                    Circle()
                        .fill(AppColors.primaryGradient)
                    Circle()
                        .fill(text.isEmpty ? Color.gray.opacity(0.3) : Color.clear)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(text.isEmpty ? .secondary : .white)
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(text.isEmpty || isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .overlay(Divider(), alignment: .top)
        )
    }

    private func toggleRecording() {
        if VoiceService.shared.isRecording {
            VoiceService.shared.stopRecording()
            if !VoiceService.shared.transcript.isEmpty {
                text = VoiceService.shared.transcript
            } else {
                // 语音识别结果为空
                let errorMsg = Message(
                    role: .system,
                    content: "未识别到语音，请重试"
                )
                state.appendMessage(errorMsg)
            }
        } else {
            Task {
                let authorized = await VoiceService.shared.requestAuthorization()
                if authorized {
                    do {
                        try VoiceService.shared.startRecording()
                    } catch {
                        let errorMsg = Message(
                            role: .system,
                            content: "语音识别失败：\(error.localizedDescription)"
                        )
                        state.appendMessage(errorMsg)
                    }
                } else {
                    let errorMsg = Message(
                        role: .system,
                        content: "语音识别未授权，请在系统设置 > 隐私与安全性 > 语音识别中开启"
                    )
                    state.appendMessage(errorMsg)
                }
            }
        }
    }
}