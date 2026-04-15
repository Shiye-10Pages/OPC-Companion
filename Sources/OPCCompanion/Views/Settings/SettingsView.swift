import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var systemPromptText = ""
    @State private var debounceTimer: Timer?
    @State private var showingTaskSheet = false
    @State private var editingTask: ScheduledTask?
    @State private var selectedVoice = ""
    @State private var selectedProvider = "siliconflow"
    @State private var apiKey = ""
    @State private var customBaseURL = ""
    @State private var connectionStatus = ""
    @State private var proxyEnabled = false
    @State private var proxyHost = "127.0.0.1"
    @State private var proxyPort = 7890

    private var availableVoices: [AVSpeechSynthesisVoice] {
        TTSService.availableVoices()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 系统提示词
                VStack(alignment: .leading, spacing: 8) {
                    Text("系统提示词")
                        .font(.headline)

                    TextEditor(text: $systemPromptText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 150)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(8)
                        .onChange(of: systemPromptText) { _, newValue in
                            debounceSave(newValue)
                        }
                }

                Divider()

                // 定时任务
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("定时任务")
                            .font(.headline)
                        Spacer()
                        Button {
                            editingTask = nil
                            showingTaskSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.bordered)
                    }

                    if state.scheduledTasks.isEmpty {
                        Text("暂无定时任务")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(state.scheduledTasks) { task in
                            ScheduledTaskRow(task: task) {
                                editingTask = task
                                showingTaskSheet = true
                            }
                        }
                    }
                }

                Divider()

                // 语音选择
                VStack(alignment: .leading, spacing: 12) {
                    Text("语音合成")
                        .font(.headline)

                    Picker("语音", selection: $selectedVoice) {
                        ForEach(availableVoices, id: \.identifier) { voice in
                            Text(TTSService.voiceDisplayName(voice))
                                .tag(voice.identifier)
                        }
                    }
                    .onChange(of: selectedVoice) { _, newValue in
                        state.config.voice.ttsVoice = newValue
                        state.saveConfig()
                    }
                }

                Divider()

                // API 配置
                VStack(alignment: .leading, spacing: 12) {
                    Text("API 配置")
                        .font(.headline)

                    Picker("提供商", selection: $selectedProvider) {
                        Text("MiniMax (海外版)").tag("minimax")
                        Text("SiliconFlow").tag("siliconflow")
                        Text("自定义").tag("custom")
                    }
                    .onChange(of: selectedProvider) { _, newValue in
                        state.config.apiConfig.provider = newValue
                        // 切换时更新默认 URL
                        if newValue == "minimax" {
                            state.config.apiConfig.baseURL = "https://api.minimax.chat/v1"
                        } else if newValue == "siliconflow" {
                            state.config.apiConfig.baseURL = "https://api.siliconflow.cn/v1"
                        }
                        state.saveConfig()
                        state.saveConfig()
                    }

                    TextField("API Key (sk-...)", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiKey) { _, newValue in
                            state.config.apiConfig.apiKey = newValue
                            state.saveConfig()
                        }

                    if selectedProvider == "custom" {
                        TextField("API 地址", text: $customBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: customBaseURL) { _, newValue in
                                state.config.apiConfig.baseURL = newValue
                                state.saveConfig()
                            }
                    }

                    Button("测试连接") {
                        testAPIConnection()
                    }
                    .buttonStyle(.bordered)
                    .disabled(apiKey.isEmpty)

                    if connectionStatus != "" {
                        Text(connectionStatus)
                            .font(.caption)
                            .foregroundColor(connectionStatus.contains("成功") ? .green : .red)
                    }
                }

                Divider()

                // 代理配置
                VStack(alignment: .leading, spacing: 12) {
                    Text("代理配置")
                        .font(.headline)

                    Toggle("启用代理", isOn: $proxyEnabled)
                        .onChange(of: proxyEnabled) { _, newValue in
                            state.config.proxyConfig.enabled = newValue
                            state.saveConfig()
                        }

                    if proxyEnabled {
                        HStack {
                            TextField("主机", text: $proxyHost)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: proxyHost) { _, newValue in
                                    state.config.proxyConfig.host = newValue
                                    state.saveConfig()
                                }

                            TextField("端口", value: $proxyPort, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: proxyPort) { _, newValue in
                                    state.config.proxyConfig.port = newValue
                                    state.saveConfig()
                                }
                        }
                    }
                }

                Divider()

                // 连接状态
                VStack(alignment: .leading, spacing: 12) {
                    Text("连接状态")
                        .font(.headline)

                    HStack(spacing: 16) {
                        StatusIndicator(name: "Notion", isConnected: checkNotionConnection())
                        StatusIndicator(name: "Claude CLI", isConnected: checkClaudeConnection())
                    }
                }

                Spacer()
            }
            .padding(16)
        }
        .onAppear {
            systemPromptText = state.systemPrompt
            selectedVoice = state.config.voice.ttsVoice
        }
        .sheet(isPresented: $showingTaskSheet) {
            ScheduledTaskForm(
                task: editingTask,
                onSave: { newTask in
                    if let index = state.scheduledTasks.firstIndex(where: { $0.id == newTask.id }) {
                        state.scheduledTasks[index] = newTask
                    } else {
                        state.scheduledTasks.append(newTask)
                    }
                    state.saveScheduledTasks()
                },
                onDelete: { task in
                    state.scheduledTasks.removeAll { $0.id == task.id }
                    state.saveScheduledTasks()
                }
            )
        }
    }

    private func debounceSave(_ text: String) {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in
            Task { @MainActor in
                state.systemPrompt = text
                state.saveSystemPrompt()
            }
        }
    }

    private func checkNotionConnection() -> Bool {
        // return NotionSyncManager.shared.isConnected
        let mcpPath = Bundle.main.path(forResource: "notion-mcp", ofType: "json")
        return mcpPath != nil
    }

    private func syncFromNotion() async {
        await NotionSyncManager.shared.syncFromNotion()
    }

    private func checkClaudeConnection() -> Bool {
        FileManager.default.fileExists(atPath: "/Users/shiye/.local/bin/claude")
    }

    private func testAPIConnection() {
        guard !apiKey.isEmpty else {
            connectionStatus = "请先输入 API Key"
            return
        }

        connectionStatus = "测试中..."

        Task {
            do {
                let testPrompt = "Say 'ok' if you receive this."
                let response = try await ChatEngine.shared.sendMessage(testPrompt, systemPrompt: "")
                if response.lowercased().contains("ok") || !response.isEmpty {
                    connectionStatus = "连接成功！"
                } else {
                    connectionStatus = "响应异常：\(response.prefix(50))"
                }
            } catch {
                connectionStatus = "连接失败: \(error.localizedDescription)"
            }
        }
    }
}

struct ScheduledTaskRow: View {
    let task: ScheduledTask
    @EnvironmentObject var state: AppState
    let onEdit: () -> Void

    var body: some View {
        HStack {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.name)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Text("\(task.time) · \(scheduleDescription(task.schedule))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Toggle("", isOn: Binding(
                get: { task.enabled },
                set: { newValue in
                    if let index = state.scheduledTasks.firstIndex(where: { $0.id == task.id }) {
                        state.scheduledTasks[index].enabled = newValue
                        state.saveScheduledTasks()
                    }
                }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private func scheduleDescription(_ schedule: TaskSchedule) -> String {
        switch schedule {
        case .daily:
            return "每天"
        case .weekly(let weekday):
            return weekday.chineseName
        case .cron:
            return "自定义"
        }
    }
}

struct ScheduledTaskForm: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss

    let task: ScheduledTask?
    let onSave: (ScheduledTask) -> Void
    let onDelete: (ScheduledTask) -> Void

    @State private var name = ""
    @State private var time = Date()
    @State private var scheduleType: ScheduleType = .daily
    @State private var weekday: TaskSchedule.Weekday = .monday
    @State private var prompt = ""
    @State private var enabled = true

    enum ScheduleType: String, CaseIterable {
        case daily = "每天"
        case weekly = "每周"
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(task == nil ? "新建定时任务" : "编辑定时任务")
                .font(.headline)

            Form {
                TextField("任务名称", text: $name)
                    .textFieldStyle(.roundedBorder)

                DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute)

                Picker("周期", selection: $scheduleType) {
                    ForEach(ScheduleType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                if scheduleType == .weekly {
                    Picker("星期", selection: $weekday) {
                        ForEach(TaskSchedule.Weekday.allCases, id: \.self) { day in
                            Text(day.chineseName).tag(day)
                        }
                    }
                }

                TextField("提醒内容", text: $prompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                Toggle("启用", isOn: $enabled)
            }

            HStack {
                if task != nil {
                    Button("删除") {
                        onDelete(task!)
                        dismiss()
                    }
                    .foregroundColor(.red)
                }

                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    let newTask = ScheduledTask(
                        id: task?.id ?? UUID(),
                        name: name,
                        time: formatTime(time),
                        schedule: scheduleType == .daily ? .daily : .weekly(weekday),
                        prompt: prompt,
                        enabled: enabled
                    )
                    onSave(newTask)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || prompt.isEmpty)
            }
        }
        .padding()
        .frame(width: 350, height: 400)
        .onAppear {
            if let task = task {
                name = task.name
                prompt = task.prompt
                enabled = task.enabled

                if let date = parseTime(task.time) {
                    time = date
                }

                switch task.schedule {
                case .daily:
                    scheduleType = .daily
                case .weekly(let w):
                    scheduleType = .weekly
                    weekday = w
                case .cron:
                    scheduleType = .daily
                }
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func parseTime(_ timeString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        if let date = formatter.date(from: timeString) {
            let calendar = Calendar.current
            let now = Date()
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            let timeComponents = calendar.dateComponents([.hour, .minute], from: date)
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            return calendar.date(from: components)
        }
        return nil
    }
}

struct StatusIndicator: View {
    let name: String
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(name)
                .font(.subheadline)
        }
    }
}

struct SettingsPopoverView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OPC 伴侣")
                .font(.headline)

            if state.hasUnreadReminders {
                HStack {
                    Image(systemName: "bell.fill")
                        .foregroundColor(.red)
                    Text("有新提醒")
                }
            } else {
                Text("暂无新提醒")
                    .foregroundColor(.secondary)
            }

            Divider()

            Button {
                AppDelegate.shared.showPanel()
            } label: {
                Text("打开主面板")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 280)
    }
}