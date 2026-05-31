import SwiftUI

struct QuietMomentDashboard: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme
    @Environment(\.fontStyle) private var fontStyle

    private var pendingTasks: [TaskItem] {
        state.tasks.filter { $0.status == .pending }
    }

    private var pendingThoughts: [Note] {
        state.notes.filter { $0.status == .pending || $0.status == .expired }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("此刻")
                            .font(fontStyle.titleFont)
                            .foregroundStyle(theme.textSecondary)
                        Text(primaryLine)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    Text(statusLine)
                        .font(fontStyle.monoFont)
                        .foregroundStyle(theme.textTertiary)
                }

                HStack(spacing: 8) {
                    QuietMetric(label: "下一步", value: nextLine)
                    QuietMetric(label: "浮念", value: "\(pendingThoughts.count) 条")
                    QuietMetric(label: "任务", value: "\(pendingTasks.count) 待定")
                }

                HStack(spacing: 8) {
                    if let active = activeTask {
                        QuietActionButton(title: "完成", icon: "checkmark.circle") {
                            state.completeCurrentTimer()
                        }
                        QuietActionButton(title: "延长 10 分", icon: "plus.circle") {
                            state.extendCurrentTimer(by: 10)
                        }
                        Text(active.title)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    } else if let next = pendingTasks.first {
                        QuietActionButton(title: "开始 25 分钟", icon: "play.circle") {
                            state.startTimer(task: next.title, minutes: 25)
                        }
                    } else {
                        QuietActionButton(title: "今天先定 3 件事", icon: "sunrise") {
                            state.showMorningRitual = true
                        }
                    }

                    Spacer(minLength: 8)

                    QuietActionButton(title: "记一下", icon: "square.and.pencil") {
                        AppDelegate.shared?.showQuickCapture()
                    }
                    QuietActionButton(title: "整理浮念", icon: "tray") {
                        withAnimation(AppAnimations.smooth) {
                            state.selectedTab = .inbox
                        }
                    }
                    QuietActionButton(title: "聊聊", icon: "sparkles") {
                        let anchor = state.activeTask?.title ?? pendingTasks.first?.title
                        state.startWishClearingSession(anchorTask: anchor)
                        state.showBanner("已进入我想清扫", kind: .info, duration: 2.0)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.textTertiary.opacity(0.16), lineWidth: 0.5)
            )
        }
    }

    private var activeTask: TaskItem? {
        guard let active = state.activeTask, active.status == .inProgress else { return nil }
        return active
    }

    private var primaryLine: String {
        if let active = activeTask {
            return active.title
        }
        if let next = pendingTasks.first {
            return next.title
        }
        if pendingThoughts.isEmpty {
            return "静场"
        }
        return "先整理浮念"
    }

    private var statusLine: String {
        guard let active = activeTask, let seconds = active.remainingSeconds else {
            return pendingThoughts.isEmpty ? "READY" : "FLOATING \(pendingThoughts.count)"
        }
        return formatRemaining(seconds)
    }

    private var nextLine: String {
        if activeTask != nil {
            return "保持当前"
        }
        if pendingTasks.first != nil {
            return "启动计时"
        }
        if pendingThoughts.isEmpty {
            return "无动作"
        }
        return "分拣"
    }

    private func formatRemaining(_ seconds: Int) -> String {
        String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}

private struct QuietMetric: View {
    let label: String
    let value: String
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuietActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? theme.textPrimary : theme.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovering ? theme.textTertiary.opacity(0.14) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct FloatingThoughtsScene: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme

    private var pendingCount: Int {
        state.notes.filter { $0.status == .pending || $0.status == .expired }.count
    }

    private var wishCount: Int {
        state.notes.filter { ($0.status == .pending || $0.status == .expired) && $0.kind == .wish }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            QuietSceneHeader(
                title: "浮念",
                subtitle: "先接住，再分拣。不默认变任务。",
                trailing: "\(pendingCount) 条"
            ) {
                HStack(spacing: 8) {
                    QuietHeaderButton(title: "新记", icon: "square.and.pencil") {
                        AppDelegate.shared?.showQuickCapture()
                    }
                    QuietHeaderButton(title: wishCount > 0 ? "清扫 \(wishCount)" : "清扫", icon: "sparkles") {
                        let anchor = state.activeTask?.title ?? state.tasks.first(where: { $0.status == .pending })?.title
                        state.startWishClearingSession(anchorTask: anchor)
                        state.wishClearingFocusNoteID = state.wishClearingCandidates.first?.id
                        state.selectedTab = .chat
                    }
                    QuietHeaderButton(title: "一键整理", icon: "wand.and.stars") {
                        Task { await state.organizePendingNotes() }
                    }
                    .disabled(state.isOrganizing || pendingCount == 0)
                }
            }

            Divider().opacity(0.5)

            InboxView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct QuietWishClearingDesk: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme
    @Environment(\.fontStyle) private var fontStyle
    @State private var reason = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            VStack(alignment: .leading, spacing: 10) {
                header

                if let note = state.currentWishClearingNote {
                    wishCard(note)
                    decisionRow(note)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.accent.opacity(0.24), lineWidth: 0.7)
            )
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("我想清扫")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(sessionSubtitle)
                    .font(fontStyle.systemMsgFont)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Button {
                state.endWishClearingSession()
                state.showBanner("已结束我想清扫", kind: .success, duration: 2.0)
            } label: {
                Label("结束", systemImage: "xmark.circle")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var sessionSubtitle: String {
        guard let session = state.wishClearingSession else { return "未开始" }
        let remaining = session.remainingSeconds
        let min = max(0, remaining) / 60
        let sec = max(0, remaining) % 60
        let anchor = session.anchorTask.map { " · 回到 \($0)" } ?? ""
        return "剩 \(String(format: "%02d:%02d", min, sec)) · 已处理 \(session.processedCount)\(anchor)"
    }

    private func wishCard(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(note.kind == .wish ? "我想" : "浮念", systemImage: note.kind == .wish ? "sparkles" : "tray")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(note.kind == .wish ? theme.accent : theme.gold)
                Spacer()
                Text(formatTime(note.capturedAt))
                    .font(fontStyle.timestampFont)
                    .foregroundStyle(theme.textTertiary)
            }
            Text(note.content)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(theme.textTertiary.opacity(0.14), lineWidth: 0.5)
        )
    }

    private func decisionRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("为什么这样处理，可不填", text: $reason)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.30))
                )

            HStack(spacing: 7) {
                decisionButton("现在做", icon: "play.circle", decision: .now, note: note)
                decisionButton("转任务", icon: "arrow.right.circle", decision: .promote, note: note)
                decisionButton("先留着", icon: "tray", decision: .keep, note: note)
                decisionButton("删除", icon: "trash", decision: .delete, note: note)
                Spacer()
                Text("剩 \(state.wishClearingCandidates.count) 条")
                    .font(fontStyle.timestampFont)
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private func decisionButton(_ title: String, icon: String, decision: WishClearingDecision, note: Note) -> some View {
        Group {
            if decision == .delete {
                Button {
                    decide(note, decision: decision)
                } label: {
                    Label(title, systemImage: icon)
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Color(nsColor: .systemRed))
            } else {
                Button {
                    decide(note, decision: decision)
                } label: {
                    Label(title, systemImage: icon)
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(theme.accent)
            }
        }
    }

    private func decide(_ note: Note, decision: WishClearingDecision) {
        let snapshot = reason
        reason = ""
        withAnimation(AppAnimations.quick) {
            state.decideWish(note, decision: decision, reason: snapshot)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 22))
                .foregroundStyle(theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("这一轮已经清完")
                    .font(.system(size: 14, weight: .semibold))
                Text("结束后回到此刻。")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Button("回到此刻") {
                state.endWishClearingSession()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 8)
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

struct ClosureScene: View {
    @EnvironmentObject var state: AppState

    private var doneToday: Int {
        state.tasks.filter { $0.status == .done }.count
    }

    private var pendingThoughts: Int {
        state.notes.filter { $0.status == .pending || $0.status == .expired }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            QuietSceneHeader(
                title: "收束",
                subtitle: "事情结束后，留下痕迹，然后退出。",
                trailing: "完成 \(doneToday)"
            ) {
                HStack(spacing: 8) {
                    QuietHeaderPill(text: "浮念 \(pendingThoughts)")
                    QuietHeaderButton(title: "回到此刻", icon: "arrow.uturn.left") {
                        state.selectedTab = .chat
                    }
                }
            }

            Divider().opacity(0.5)

            HistoryView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct QuietSceneHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    let trailing: String
    let actions: Actions
    @Environment(\.theme) private var theme
    @Environment(\.fontStyle) private var fontStyle

    init(
        title: String,
        subtitle: String,
        trailing: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(subtitle)
                        .font(fontStyle.systemMsgFont)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Text(trailing)
                    .font(fontStyle.monoFont)
                    .foregroundStyle(theme.textTertiary)
            }
            actions
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

private struct QuietHeaderButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textSecondary)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

private struct QuietHeaderPill: View {
    let text: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(theme.textTertiary.opacity(0.10))
            )
    }
}
