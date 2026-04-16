import SwiftUI

struct StatusBarPopoverView: View {
    @EnvironmentObject var state: AppState

    private var pendingTasks: [TaskItem] {
        state.tasks.filter { $0.status == .pending }
    }

    private var upcomingScheduled: [ScheduledTask] {
        let now = Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        let hm = DateFormatter()
        hm.dateFormat = "HH:mm"
        let nowString = hm.string(from: now)

        return state.scheduledTasks
            .filter { task in
                guard task.enabled else { return false }
                switch task.schedule {
                case .daily: break
                case .weekly(let w): if w.rawValue != weekday { return false }
                case .cron: return false
                }
                return task.time > nowString
            }
            .sorted { $0.time < $1.time }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let active = state.activeTask, active.status == .inProgress {
                        activeTaskSection(active)
                    }

                    if !upcomingScheduled.isEmpty {
                        sectionTitle("今日即将到来", icon: "calendar")
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(upcomingScheduled) { task in
                                upcomingRow(task)
                            }
                        }
                    }

                    if !pendingTasks.isEmpty {
                        sectionTitle("待处理 (\(pendingTasks.count))", icon: "list.bullet")
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(pendingTasks.prefix(5)) { task in
                                pendingRow(task)
                            }
                            if pendingTasks.count > 5 {
                                Text("还有 \(pendingTasks.count - 5) 条…")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)
                            }
                        }
                    }

                    if state.activeTask == nil && upcomingScheduled.isEmpty && pendingTasks.isEmpty {
                        idleState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)

            Divider()
            footer
        }
        .frame(width: 340, height: 420)
    }

    // MARK: - 子视图

    private var header: some View {
        HStack {
            Image(systemName: "bubble.left.fill")
                .foregroundColor(AppColors.primary)
            Text("OPC 伴侣")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(currentTime())
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func sectionTitle(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.secondary)
    }

    private func activeTaskSection(_ task: TaskItem) -> some View {
        // 用 TimelineView 每秒驱动 remainingSeconds 重算
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(AppColors.taskInProgress)
                        .frame(width: 8, height: 8)
                    Text("进行中")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppColors.taskInProgress)
                    Spacer()
                }
                HStack {
                    Text(task.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    if let remaining = task.remainingSeconds {
                        Text(formatDuration(remaining))
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundColor(remaining < 300 ? AppColors.statusError : .primary)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppColors.taskInProgress.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppColors.taskInProgress.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private func upcomingRow(_ task: ScheduledTask) -> some View {
        HStack(spacing: 8) {
            Text(task.time)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(task.name)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private func pendingRow(_ task: TaskItem) -> some View {
        HStack(spacing: 8) {
            Circle()
                .stroke(Color.secondary, lineWidth: 1)
                .frame(width: 8, height: 8)
            Text(task.title)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private var idleState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 24))
                .foregroundColor(.secondary)
            Text("暂无进行中的任务")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("按 Option+Space 打开主面板开始")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: openPanel) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.expand.vertical")
                    Text("打开面板")
                }
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)

            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(action: quit) {
                Image(systemName: "power")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.statusError)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func openPanel() {
        AppDelegate.shared?.popover?.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            AppDelegate.shared?.showPanel()
        }
    }

    private func openSettings() {
        AppDelegate.shared?.popover?.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            AppDelegate.shared?.showPanel()
            AppState.shared.selectedTab = .settings
        }
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Helpers

    private func currentTime() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

struct StatusBarPopoverView_Previews: PreviewProvider {
    static var previews: some View {
        StatusBarPopoverView()
            .environmentObject(AppState.shared)
    }
}
