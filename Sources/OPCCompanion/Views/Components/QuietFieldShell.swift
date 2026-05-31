import SwiftUI

/// Quiet Field 新前门原型（v2 设计稿 §4–§6）：折叠 bar ↔ 卷帘展开。
///
/// 自包含、读真实 AppState；折叠态毛玻璃背景，不碰 AppDelegate 那套 NSVisualEffectView /
/// 圆角裁切。挂在独立预览面板（AppDelegate.showQuietFieldPreview），不影响现有主面板。
///
/// 折叠 bar 保持纯粹：一行输入 + 「聊聊」「⌄ 下拉」两个入口，没有状态行/浮念等下一层文字。
/// 所有更进一步的交互（此刻状态 / 浮念分拣 / 清扫 / 收束）都在展开窗口里。
/// 聊聊接真 AI（ChatEngine 流式）；展开背景用真·主题动画背景，对标主面板。
struct QuietFieldShell: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme
    @Environment(\.fontStyle) private var fontStyle

    enum BarMode { case note, chat }                        // 随手记 ↔ 聊聊
    enum Screen { case moment, inbox, clearing, closure, settings }   // 展开层当前场景

    @State private var expanded = false
    @State private var appeared = false
    @State private var mode: BarMode = .note
    @State private var screen: Screen = .moment
    @State private var inputText = ""
    @State private var captured = false
    @FocusState private var inputFocused: Bool

    private let cardWidth: CGFloat = 524
    private let revealHeight: CGFloat = 460

    var body: some View {
        ZStack {
            card
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 16)

            proactiveOverlays
        }
        .animation(AppAnimations.quick, value: state.postMortemQueue.count)
        .animation(AppAnimations.quick, value: state.showDreamingReview)
        .animation(AppAnimations.quick, value: state.nextCandidates.count)
        .onAppear {
            focusSoon()
            withAnimation(theme.panelEntrance) { appeared = true }
        }
    }

    /// 主动介入浮层（对标主面板 MainTabView）：早晨仪式 / 完成复盘 / 学习审核 / 下一件候选。
    @ViewBuilder
    private var proactiveOverlays: some View {
        if let pending = state.postMortemQueue.first {
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()
                    .onTapGesture { state.dequeuePostMortem() }
                PostMortemView(task: pending)
            }
            .transition(.opacity)
        }
        if state.showDreamingReview && !state.pendingLearnings.isEmpty {
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()
                    .onTapGesture { state.markDreamingReviewDone() }
                DreamingReviewView()
            }
            .transition(.opacity)
        }
        if !state.nextCandidates.isEmpty {
            NextCandidatesView()
                .padding(.trailing, 16)
                .padding(.bottom, 80)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: - 卡片（折叠 ↔ 展开同一张，向下卷帘长高）

    private var card: some View {
        VStack(spacing: 0) {
            revealArea
                .frame(height: expanded ? revealHeight : 0)
                .opacity(expanded ? 1 : 0)
                .clipped()

            inputRegion   // 永远是最后一个孩子 → 揭示区在它上方长出，它从顶滑到底
        }
        .frame(width: cardWidth)
        .background(
            // GeometryReader 把背景焊死在卡片尺寸内：theme.background 内部带 .ignoresSafeArea()，
            // 不焊会挣脱裁切把整个面板填满。.clipped() 再硬裁一道兜底。
            GeometryReader { geo in
                ZStack {
                    if expanded {
                        theme.background        // 展开：真·主题动画背景（Aurora 漂移光团等）
                        BurstFlash(accent: theme.accent)
                            .allowsHitTesting(false)
                    } else {
                        Rectangle().fill(.regularMaterial)   // 折叠：干净毛玻璃单行 bar
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: theme.panelCornerRadius, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.panelCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
        .overlay(alignment: .top) {
            if captured { capturedFlash }
        }
        .overlay(alignment: .top) {
            if let banner = state.banner {
                BannerView(message: banner)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(banner.id)
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 30, x: 0, y: 16)
        .shadow(color: .black.opacity(0.07), radius: 2, x: 0, y: 1)
        .animation(AppAnimations.smooth, value: expanded)
        .animation(AppAnimations.smooth, value: state.banner?.id)
        .onChange(of: state.wishClearingSession == nil) { _, isNil in
            // 清扫会话被结束（桌内"结束"按钮）→ 自动退回此刻
            if isNil && screen == .clearing {
                withAnimation(AppAnimations.smooth) { screen = .moment }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - 揭示区（展开内容：此刻 / 浮念分拣 / 清扫 / 收束）

    @ViewBuilder
    private var revealArea: some View {
        switch screen {
        case .moment:
            VStack(spacing: 0) {
                dashboardHeader
                Divider().opacity(0.3)
                if state.showProgressPingPanel {
                    ProgressPingView()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                conversation
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .inbox:
            VStack(spacing: 0) {
                activityHeader(title: "浮念", trailing: "\(pendingThoughts.count) 条") {
                    activityButton("清扫", icon: "sparkles") { enterClearing() }
                        .disabled(pendingThoughts.isEmpty)
                    backButton
                }
                Divider().opacity(0.3)
                InboxView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .clearing:
            VStack(spacing: 0) {
                QuietWishClearingDesk()
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                Spacer(minLength: 0)
            }
        case .closure:
            VStack(spacing: 0) {
                activityHeader(title: "收束", trailing: "完成 \(doneToday)") {
                    backButton
                }
                Divider().opacity(0.3)
                HistoryView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .settings:
            VStack(spacing: 0) {
                activityHeader(title: "设置", trailing: "") {
                    backButton
                }
                Divider().opacity(0.3)
                SettingsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// 一条安静的"此刻"上下文行 + 进一步入口（浮念 / 收束）。这些入口只活在展开窗口里。
    private var dashboardHeader: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Text(headerLine)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)

                    if let a = activeTask, let s = a.remainingSeconds {
                        Text(mmss(s))
                            .font(fontStyle.monoFont)
                            .foregroundStyle(theme.textTertiary)
                    }

                    Spacer(minLength: 8)

                    if activeTask != nil {
                        headerAction("完成") { state.completeCurrentTimer() }
                        headerAction("延长") { state.extendCurrentTimer(by: 10) }
                    }

                    Button { withAnimation(AppAnimations.smooth) { screen = .settings } } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.textTertiary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("设置")

                    Button { collapse() } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("收起")
                }

                HStack(spacing: 8) {
                    momentEntry("浮念 \(pendingThoughts.count)", icon: "tray") { enterInbox() }
                    momentEntry("收束", icon: "checkmark.seal") { enterClosure() }
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if renderedMessages.isEmpty && !state.isLoading {
                    Text("问整理员一句，拿一条短回复")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 44)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(renderedMessages) { msg in
                            MessageBubble(message: msg).id(msg.id)
                        }
                        if state.isLoading {
                            TypingIndicator()
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
            }
            .onChange(of: state.messages.count) { _, _ in
                withAnimation(AppAnimations.quick) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: state.messages.last?.content ?? "") { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var renderedMessages: [Message] {
        state.messages.filter { msg in
            guard !msg.hidden else { return false }
            if msg.role == .assistant && msg.content.isEmpty { return false }
            return true
        }
    }

    // MARK: - 输入区（折叠：纯单行 pill + 聊聊 / 下拉两个入口；展开：纯输入）

    private var inputRegion: some View {
        HStack(spacing: 10) {
            Image(systemName: mode == .note ? "tray.and.arrow.down" : "sparkles")
                .font(.system(size: 15))
                .foregroundStyle(mode == .note ? theme.textSecondary : theme.accent)

            TextField(inputPlaceholder, text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($inputFocused)
                .onSubmit(handleSubmit)

            if !expanded {
                // 随手记 ↔ 聊聊 切换 + 下拉展开。bar 其余保持纯粹，无状态行。
                modeChip

                Button { expand() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("展开更多")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: theme.inputCornerRadius, style: .continuous)
                .fill(AppColors.inputBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.inputCornerRadius, style: .continuous)
                .stroke(inputFocused ? theme.accent.opacity(0.55) : Color.primary.opacity(0.08),
                        lineWidth: 1)
        )
        .shadow(color: inputFocused ? theme.accent.opacity(0.18) : .clear, radius: 8, x: 0, y: 3)
        .padding(14)
    }

    /// 随手记 ↔ 聊聊 切换：只切输入模式（本地接住 / 发给 AI），不直接展开。
    private var modeChip: some View {
        Button {
            withAnimation(AppAnimations.quick) { mode = (mode == .note) ? .chat : .note }
        } label: {
            Text(mode == .chat ? "聊聊" : "随手记")
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(mode == .chat ? theme.accent.opacity(0.18) : theme.textTertiary.opacity(0.12))
                )
                .foregroundStyle(mode == .chat ? theme.accent : theme.textSecondary)
        }
        .buttonStyle(.plain)
        .help(mode == .chat ? "聊聊：问整理员，会发给 AI" : "随手记：本地接住，不走 AI")
    }

    // MARK: - 提交

    private func handleSubmit() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if expanded || mode == .chat {
            // 展开层、或折叠态切到聊聊 = 对话（折叠时自动卷帘展开）
            inputText = ""
            if !expanded { withAnimation(AppAnimations.smooth) { expanded = true } }
            sendToAI(trimmed)
        } else {
            // 折叠 = 记一下：本地接住，不走 AI；闪一下"已接住"，随即关闭
            state.captureNote(content: trimmed, source: .hotkeyText, inputMode: .text, kind: .note)
            inputText = ""
            withAnimation(AppAnimations.quick) { captured = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                AppDelegate.shared?.hideQuietFieldPreview()
            }
        }
    }

    /// 真实 AI 流式发送（镜像 ChatView.sendMessage 核心，简化掉斜杠/wish 分支）。
    private func sendToAI(_ userMessage: String) {
        guard !state.isLoading else { return }
        state.appendMessage(Message(role: .user, content: userMessage, inputMode: .text))

        if let timer = ChatEngine.detectLocalTimer(in: userMessage) {
            state.startTimer(task: timer.task, minutes: timer.minutes)
        }

        let placeholder = Message(role: .assistant, content: "", inputMode: .text)
        state.appendMessage(placeholder)
        let msgID = placeholder.id
        state.isLoading = true

        Task { @MainActor in
            defer {
                state.persistMessage(id: msgID)
                state.isLoading = false
            }
            do {
                let composed = ThemeProvider.shared.composedPrompt(base: state.systemPrompt)
                let response = try await ChatEngine.shared.sendMessage(
                    userMessage,
                    systemPrompt: composed,
                    onAssistantDelta: { delta in
                        Task { @MainActor in
                            if let idx = AppState.shared.messages.firstIndex(where: { $0.id == msgID }) {
                                AppState.shared.messages[idx].content += delta
                            }
                        }
                    }
                )
                if let idx = state.messages.firstIndex(where: { $0.id == msgID }),
                   state.messages[idx].content.count < response.count {
                    state.messages[idx].content = response
                }
            } catch {
                if let idx = state.messages.firstIndex(where: { $0.id == msgID }) {
                    let partial = state.messages[idx].content
                    state.messages[idx].content = partial.isEmpty
                        ? "抱歉，出了点问题：\(error.localizedDescription)"
                        : partial + "\n\n— [连接中断: \(error.localizedDescription)]"
                }
                state.showBanner("消息发送失败：\(error.localizedDescription)", kind: .error, duration: 5.0)
            }
        }
    }

    private func focusSoon() {
        DispatchQueue.main.async { inputFocused = true }
    }

    // MARK: - 展开 / 活动（浮念分拣 / 清扫 / 收束）进出

    private func expand() {
        withAnimation(AppAnimations.smooth) { screen = .moment; expanded = true }
    }

    private func collapse() {
        withAnimation(AppAnimations.smooth) {
            screen = .moment
            expanded = false
        }
    }

    private func enterInbox() {
        withAnimation(AppAnimations.smooth) { screen = .inbox; expanded = true }
    }

    private func enterClosure() {
        withAnimation(AppAnimations.smooth) { screen = .closure; expanded = true }
    }

    private func enterClearing() {
        let anchor = activeTask?.title ?? pendingTasks.first?.title
        state.startWishClearingSession(anchorTask: anchor)
        state.wishClearingFocusNoteID = state.wishClearingCandidates.first?.id
        withAnimation(AppAnimations.smooth) { screen = .clearing; expanded = true }
    }

    // MARK: - 子件

    private func headerAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func momentEntry(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(theme.textTertiary.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func activityHeader<A: View>(title: String, trailing: String, @ViewBuilder actions: () -> A) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text(trailing)
                .font(fontStyle.monoFont)
                .foregroundStyle(theme.textTertiary)
            Spacer(minLength: 8)
            actions()
            Button { collapse() } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("收起")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func activityButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.accent)
        }
        .buttonStyle(.plain)
    }

    private var backButton: some View {
        Button {
            withAnimation(AppAnimations.smooth) { screen = .moment }
        } label: {
            Label("此刻", systemImage: "arrow.uturn.left")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textSecondary)
        }
        .buttonStyle(.plain)
        .help("返回此刻")
    }

    private var capturedFlash: some View {
        Text("已接住")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().stroke(theme.accent.opacity(0.3), lineWidth: 0.5))
            .padding(.top, -13)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - 派生状态

    private var activeTask: TaskItem? {
        guard let a = state.activeTask, a.status == .inProgress else { return nil }
        return a
    }
    private var pendingTasks: [TaskItem] { state.tasks.filter { $0.status == .pending } }
    private var pendingThoughts: [Note] { state.notes.filter { $0.status == .pending || $0.status == .expired } }
    private var doneToday: Int { state.tasks.filter { $0.status == .done }.count }

    private var inputPlaceholder: String {
        if expanded { return "说点什么…" }
        return mode == .chat ? "问问整理员…" : "记一下想法…"
    }

    private var headerLine: String {
        if let a = activeTask { return a.title }
        if let n = pendingTasks.first { return n.title }
        return pendingThoughts.isEmpty ? "静场" : "先整理浮念"
    }

    private func mmss(_ seconds: Int) -> String {
        String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}
