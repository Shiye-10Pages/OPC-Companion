import SwiftUI

struct ChatView: View {
    @EnvironmentObject var state: AppState
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // 当日任务区
                if !state.tasks.isEmpty {
                    TaskSection()
                }

                // 对话消息区
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(state.messages) { message in
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
            .overlay(alignment: .center) {
                if NotionConfirmManager.shared.showConfirmation,
                   let action = NotionConfirmManager.shared.pendingAction {
                    NotionConfirmCard(action: action) {
                        NotionConfirmManager.shared.confirm()
                    } onCancel: {
                        let cancelMsg = Message(
                            role: .system,
                            content: "已取消 Notion 操作"
                        )
                        state.appendMessage(cancelMsg)
                        NotionConfirmManager.shared.cancel()
                    }
                }
            }
            .onAppear {
                isInputFocused = true
            }
        }
    }

    private func sendMessage() {
        // 防止并发发送
        guard !state.isLoading else { return }
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let userMessage = inputText
        inputText = ""
        isInputFocused = true

        // 检查是否是语音输入模式
        let inputMode: InputMode = VoiceService.shared.isRecording ? .voice : .text
        if inputMode == .voice {
            VoiceService.shared.stopRecording()
        }

        // 添加用户消息
        let message = Message(role: .user, content: userMessage, inputMode: inputMode)
        state.appendMessage(message)

        Task {
            state.isLoading = true

            do {
                let systemPrompt = state.systemPrompt
                let response = try await ChatEngine.shared.sendMessage(userMessage, systemPrompt: systemPrompt)

                // 添加助手消息
                let assistantMessage = Message(role: .assistant, content: response, inputMode: inputMode)
                state.appendMessage(assistantMessage)

                // 语音输入模式：朗读回复
                if inputMode == .voice {
                    TTSService.shared.speak(response, voiceId: state.config.voice.ttsVoice, rate: state.config.voice.ttsRate)
                }

                // 解析并执行 action
                let actions = ChatEngine.shared.parseActions(from: response)
                for action in actions {
                    handleAction(action)
                }
            } catch {
                let errorMessage = Message(
                    role: .system,
                    content: "抱歉，出了点问题：\(error.localizedDescription)"
                )
                state.appendMessage(errorMessage)
            }

            state.isLoading = false
        }
    }

    private func handleAction(_ action: Action) {
        switch action {
        case .timer(let timerAction):
            let task = TaskItem(
                title: timerAction.task,
                status: .inProgress,
                timerMinutes: timerAction.minutes,
                timerStart: Date(),
                timerEnd: Date().addingTimeInterval(TimeInterval(timerAction.minutes * 60))
            )
            state.tasks.append(task)
            state.activeTask = task
            state.menuBarStatus = .focus
            state.saveTasks()

        case .timerExtend(let extendAction):
            // 延长计时
            if let activeTask = state.activeTask {
                let newEnd = Date().addingTimeInterval(TimeInterval(extendAction.minutes * 60))
                if let index = state.tasks.firstIndex(where: { $0.id == activeTask.id }) {
                    state.tasks[index].timerEnd = newEnd
                    state.tasks[index].extensions += 1
                    state.activeTask = state.tasks[index]
                    state.menuBarStatus = .focus

                    // 重置 AppDelegate 中的通知状态
                    AppDelegate.shared.resetTimerNotifications()

                    let extendMsg = Message(
                        role: .system,
                        content: "已延长 \(extendAction.minutes) 分钟"
                    )
                    state.appendMessage(extendMsg)
                }
            }

        case .notion(let notionAction):
            // 显示确认卡片
            NotionConfirmManager.shared.requestConfirmation(
                action: notionAction,
                onConfirm: {
                    // 执行 Notion 操作
                    Task {
                        do {
                            let mcpPath = Bundle.main.path(forResource: "notion-mcp", ofType: "json")
                            let response = try await ChatEngine.shared.sendMessageWithMCP(
                                "执行 Notion 操作: \(notionAction.operation) \(notionAction.parameters)",
                                systemPrompt: self.state.systemPrompt,
                                mcpConfigPath: mcpPath
                            )
                            let resultMsg = Message(
                                role: .assistant,
                                content: "Notion 操作已完成：\(response)"
                            )
                            self.state.appendMessage(resultMsg)
                        } catch {
                            let errorMsg = Message(
                                role: .system,
                                content: "Notion 操作失败：\(error.localizedDescription)"
                            )
                            self.state.appendMessage(errorMsg)
                        }
                    }
                },
                onCancel: {
                    // 已在卡片处理
                }
            )
        }
    }
}

struct TaskSection: View {
    @EnvironmentObject var state: AppState
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(AppAnimations.quick) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "checklist")
                        .font(.system(size: 14, weight: .medium))
                    Text("今日任务")
                        .font(AppTypography.body.bold())

                    Spacer()

                    // 任务数量徽章
                    if !state.tasks.isEmpty {
                        Text("\(state.tasks.count)")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(AppColors.primary.opacity(0.2))
                            .cornerRadius(10)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
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
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

struct TaskCard: View {
    let task: TaskItem
    @EnvironmentObject var state: AppState

    private var statusColor: Color {
        switch task.status {
        case .pending: return .gray
        case .inProgress: return .green
        case .done: return .blue
        case .cancelled: return .red
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

            // 状态标签
            statusTag
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.button)
                .fill(Color.white.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.button)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusTag: some View {
        switch task.status {
        case .pending:
            Text("待办")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(6)
        case .inProgress:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("进行中")
            }
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.2))
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

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                MarkdownText(text: message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .cornerRadius(AppCornerRadius.bubble)
                    .shadow(color: AppShadows.bubble.color, radius: AppShadows.bubble.radius, x: AppShadows.bubble.x, y: AppShadows.bubble.y)

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

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 12)
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
        HStack(spacing: 4) {
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
        .padding(.leading, 4)
        .onAppear {
            animating = true
        }
    }
}

struct InputBar: View {
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void
    @EnvironmentObject var state: AppState
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            // 输入框容器
            HStack(spacing: 8) {
                TextField("发送消息...", text: $text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .font(AppTypography.body)
                    .onSubmit {
                        if !isLoading && !text.isEmpty {
                            onSend()
                        }
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
                    .stroke(isFocused ? AppColors.primary : Color.clear, lineWidth: 1.5)
            )

            // 麦克风按钮
            Button {
                toggleRecording()
            } label: {
                Image(systemName: VoiceService.shared.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(VoiceService.shared.isRecording ? .red : .secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(VoiceService.shared.isRecording ? .red.opacity(0.1) : Color.clear)
                    )
            }
            .buttonStyle(.plain)

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
                .fill(.ultraThinMaterial)
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