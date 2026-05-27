import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var systemPromptText = ""
    @State private var debounceTimer: Timer?
    // showingTaskSheet / editingTask 已迁到 AppState（showScheduledTaskForm + editingScheduledTask）
    @State private var selectedVoice = ""
    @State private var selectedProvider = "siliconflow"
    @State private var apiKey = ""
    @State private var customBaseURL = ""
    @State private var connectionStatus = ""
    @State private var proxyEnabled = false
    @State private var proxyHost = "127.0.0.1"
    @State private var proxyPort = 7890
    @State private var notionToken = ""
    @State private var notionDatabases: [NotionDatabase] = []
    @State private var notionLoadingDatabases = false
    @State private var notionLoadError: String?
    @State private var notionCalendarId = ""
    @State private var notionTodosId = ""
    @State private var notionInboxId = ""

    private var availableVoices: [AVSpeechSynthesisVoice] {
        TTSService.availableVoices()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                setupChecklist

                ThemeSection()

                Divider()

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
                            state.config.apiConfig.baseURL = APIConfig.miniMaxInternationalBaseURL
                        } else if newValue == "siliconflow" {
                            state.config.apiConfig.baseURL = "https://api.siliconflow.cn/v1"
                        }
                        customBaseURL = state.config.apiConfig.baseURL
                        state.saveConfig()
                        state.saveConfig()
                    }

                    SecureField("API Key（存储在 macOS Keychain）", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiKey) { _, newValue in
                            CredentialCache.shared.setMinimaxAPIKey(newValue)
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
                            .foregroundColor(connectionStatus.contains("成功") ? AppColors.statusOk : AppColors.statusError)
                    }
                }

                Divider()

                notionSection

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
                        StatusIndicator(name: "MiniMax", isConnected: checkClaudeConnection())
                    }
                }

                Spacer()
            }
            .padding(16)
        }
        .onAppear {
            systemPromptText = state.systemPrompt
            selectedVoice = state.config.voice.ttsVoice
            selectedProvider = state.config.apiConfig.provider
            apiKey = CredentialCache.shared.getMinimaxAPIKey()
            if state.config.apiConfig.provider == "minimax",
               state.config.apiConfig.baseURL == APIConfig.legacyMiniMaxBaseURL {
                state.config.apiConfig.baseURL = APIConfig.miniMaxInternationalBaseURL
                state.saveConfig()
            }
            customBaseURL = state.config.apiConfig.normalizedBaseURL
            proxyEnabled = state.config.proxyConfig.enabled
            proxyHost = state.config.proxyConfig.host
            proxyPort = state.config.proxyConfig.port
            notionToken = CredentialCache.shared.getNotionToken()
            notionCalendarId = state.config.notionDatabaseIds.calendar ?? ""
            notionTodosId = state.config.notionDatabaseIds.todos ?? ""
            notionInboxId = state.config.notionDatabaseIds.inbox ?? ""
        }
        .onDisappear {
            debounceTimer?.invalidate()
            debounceTimer = nil
        }
        // .sheet 已迁到 MainTabView overlay（showScheduledTaskForm），避免 borderless NSPanel 崩
    }

    @ViewBuilder
    private var setupChecklist: some View {
        let apiKeyOK = !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
        let notionTokenOK = !notionToken.trimmingCharacters(in: .whitespaces).isEmpty
        let dbMapped = !(notionCalendarId.isEmpty && notionTodosId.isEmpty && notionInboxId.isEmpty)
        let allDone = apiKeyOK && notionTokenOK && dbMapped

        if !allDone {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.clipboard")
                        .foregroundColor(.orange)
                    Text("配置步骤")
                        .font(.headline)
                    Spacer()
                }
                checklistRow(done: apiKeyOK, label: "填写 MiniMax API Key", required: true)
                checklistRow(done: notionTokenOK, label: "填写 Notion Token", required: false)
                checklistRow(done: dbMapped, label: "绑定至少一个 Notion 数据库", required: false)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private func checklistRow(done: Bool, label: String, required: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundColor(done ? AppColors.statusOk : .secondary)
                .font(.system(size: 14))
            Text(label)
                .font(.system(size: 12))
                .strikethrough(done)
                .foregroundColor(done ? .secondary : .primary)
            if required && !done {
                Text("必需")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .cornerRadius(4)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var notionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notion").font(.headline)

            SecureField("Notion Token（存储在 macOS Keychain）", text: $notionToken)
                .textFieldStyle(.roundedBorder)
                .onChange(of: notionToken) { _, newValue in
                    CredentialCache.shared.setNotionToken(newValue)
                }

            HStack {
                Button {
                    loadNotionDatabases()
                } label: {
                    if notionLoadingDatabases {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("刷新数据库列表")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(notionToken.isEmpty || notionLoadingDatabases)

                if let err = notionLoadError {
                    Text(err).font(.caption).foregroundColor(.red)
                } else if !notionDatabases.isEmpty {
                    Text("共 \(notionDatabases.count) 个").font(.caption).foregroundColor(.secondary)
                }
            }

            if !notionDatabases.isEmpty {
                notionMappingRow(label: "日历", selection: $notionCalendarId) { id in
                    state.config.notionDatabaseIds.calendar = id
                    state.saveConfig()
                }
                notionMappingRow(label: "待办", selection: $notionTodosId) { id in
                    state.config.notionDatabaseIds.todos = id
                    state.saveConfig()
                }
                notionMappingRow(label: "收件箱", selection: $notionInboxId) { id in
                    state.config.notionDatabaseIds.inbox = id
                    state.saveConfig()
                }
            }
        }
    }

    @ViewBuilder
    private func notionMappingRow(label: String, selection: Binding<String>, onChange: @escaping (String?) -> Void) -> some View {
        HStack {
            Text(label).frame(width: 48, alignment: .leading)
            Picker("", selection: selection) {
                Text("未选择").tag("")
                ForEach(notionDatabases) { db in
                    Text(db.title.isEmpty ? db.id.prefix(8).description : db.title).tag(db.id)
                }
            }
            .labelsHidden()
            .onChange(of: selection.wrappedValue) { _, newValue in
                onChange(newValue.isEmpty ? nil : newValue)
            }
        }
    }

    private func loadNotionDatabases() {
        notionLoadError = nil
        notionLoadingDatabases = true
        Task {
            do {
                let dbs = try await NotionService.shared.searchDatabases()
                await MainActor.run {
                    self.notionDatabases = dbs
                    self.notionLoadingDatabases = false
                }
            } catch {
                await MainActor.run {
                    self.notionLoadError = error.localizedDescription
                    self.notionLoadingDatabases = false
                }
            }
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
        !CredentialCache.shared.getNotionToken().isEmpty
    }

    private func checkClaudeConnection() -> Bool {
        !CredentialCache.shared.getMinimaxAPIKey().isEmpty
    }

    private func testAPIConnection() {
        guard !apiKey.isEmpty else {
            connectionStatus = "请先输入 API Key"
            return
        }

        connectionStatus = "测试中..."

        Task {
            do {
                if selectedProvider == "minimax" {
                    let config = APIConfig(provider: selectedProvider, apiKey: apiKey, baseURL: customBaseURL)
                    _ = try await ChatEngine.shared.testMiniMaxConnection(config: config)
                    connectionStatus = "MiniMax 连接成功！"
                } else {
                    let testPrompt = "Say 'ok' if you receive this."
                    let response = try await ChatEngine.shared.sendMessage(testPrompt, systemPrompt: "", useConversationHistory: false)
                    connectionStatus = response.isEmpty ? "响应异常：空响应" : "连接成功！"
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
        HStack(spacing: 8) {
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

            Button(action: deleteTask) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("删除定时任务")
        }
        .padding(.vertical, 4)
    }

    private func deleteTask() {
        state.scheduledTasks.removeAll { $0.id == task.id }
        state.saveScheduledTasks()
        state.showBanner("已删除：\(task.name)", kind: .info)
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

    let task: ScheduledTask?
    let onSave: (ScheduledTask) -> Void
    let onDelete: (ScheduledTask) -> Void
    let onCancel: () -> Void

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
                        onCancel()
                    }
                    .foregroundColor(.red)
                }

                Spacer()

                Button("取消") {
                    onCancel()
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
                    onCancel()
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
                .fill(isConnected ? AppColors.statusOk : AppColors.statusError)
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
