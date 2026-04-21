import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                StatusBar(activeTimerTitle: state.activeTask?.title)

                // 未锁定焦点 常驻提示（TimelineView 驱动小时判断，用户"完成仪式"后会自动消失）
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    if shouldShowRitualMissingBar() {
                        ritualMissingBar
                    }
                }

                if state.showProgressPingPanel {
                    ProgressPingView()
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ChatView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if state.selectedTab != .chat {
                popoverBackdrop
                popoverPanel
            }

            if state.showAddTaskOverlay {
                addTaskOverlay
            }
            if state.showMorningRitual {
                morningRitualOverlay
            }
            if !state.nextCandidates.isEmpty {
                nextCandidatesOverlay
            }
            if let pending = state.postMortemQueue.first {
                postMortemOverlay(task: pending)
            }
            if state.showScheduledTaskForm {
                scheduledTaskFormOverlay
            }
            if state.showDreamingReview && !state.pendingLearnings.isEmpty {
                dreamingReviewOverlay
            }
        }
        .animation(AppAnimations.quick, value: state.selectedTab)
        .animation(AppAnimations.quick, value: state.showAddTaskOverlay)
        .animation(AppAnimations.standard, value: state.showProgressPingPanel)
        .animation(AppAnimations.quick, value: state.showMorningRitual)
        .animation(AppAnimations.quick, value: state.nextCandidates.count)
        .animation(AppAnimations.quick, value: state.postMortemQueue.count)
        .animation(AppAnimations.quick, value: state.showScheduledTaskForm)
        .animation(AppAnimations.quick, value: state.showDreamingReview)
    }

    private var scheduledTaskFormOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { state.showScheduledTaskForm = false }
            ScheduledTaskForm(
                task: state.editingScheduledTask,
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
                },
                onCancel: { state.showScheduledTaskForm = false }
            )
            .glassBackground()
        }
        .transition(.opacity)
    }

    private var dreamingReviewOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { state.markDreamingReviewDone() }
            DreamingReviewView()
        }
        .transition(.opacity)
    }

    private var morningRitualOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            MorningRitualView()
        }
        .transition(.opacity)
    }

    private var nextCandidatesOverlay: some View {
        NextCandidatesView()
            .padding(.trailing, 16)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func postMortemOverlay(task: TaskItem) -> some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { state.dequeuePostMortem() }
            PostMortemView(task: task)
        }
        .transition(.opacity)
    }

    private var addTaskOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { state.showAddTaskOverlay = false }
            AddTaskSheet(
                onSave: { title, minutes, pomodoro, focus in
                    state.addOrStartTask(title: title, minutes: minutes, pomodoroCycle: pomodoro, focusMode: focus)
                    state.showAddTaskOverlay = false
                },
                onCancel: { state.showAddTaskOverlay = false }
            )
        }
        .transition(.opacity)
    }

    // 早晨仪式未做的常驻提示条：当 hour ≥ 10 且今天没做仪式时显示，做完自动消失
    private var ritualMissingBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sunrise.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .systemOrange))
            Text("今日未锁定焦点")
                .font(.system(size: 12))
                .foregroundStyle(.primary)
            Spacer()
            Button("立刻做") {
                state.showMorningRitual = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(nsColor: .systemOrange).opacity(0.08))
        .overlay(Divider().opacity(0.5), alignment: .bottom)
    }

    private func shouldShowRitualMissingBar() -> Bool {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        guard hour >= 10 else { return false }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: now)
        return state.lastMorningRitualDate != today
    }

    private var popoverBackdrop: some View {
        Color.black.opacity(0.001)
            .padding(.top, 44)
            .ignoresSafeArea(edges: [.leading, .trailing, .bottom])
            .onTapGesture { closePopover() }
            .transition(.opacity)
    }

    @ViewBuilder
    private var popoverPanel: some View {
        VStack(spacing: 0) {
            Group {
                switch state.selectedTab {
                case .tasks: TasksPopoverContent()
                case .inbox: InboxView()
                case .history: HistoryPopoverContent()
                case .settings: SettingsView()
                case .chat: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 420, height: 400)
        .glassBackground(cornerRadius: AppCornerRadius.overlay)
        .padding(.top, 50)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func closePopover() {
        withAnimation(AppAnimations.quick) {
            state.selectedTab = .chat
        }
    }
}

// MARK: - 任务 Popover：活跃 / 已完成 分 Tab，排序：进行中置顶 → 待办

struct TasksPopoverContent: View {
    @EnvironmentObject var state: AppState
    @State private var showArchived = false

    private var activeTasks: [TaskItem] {
        state.tasks
            .filter { $0.status == .inProgress || $0.status == .pending }
            .sorted { lhs, _ in lhs.status == .inProgress }
    }

    private var archivedTasks: [TaskItem] {
        state.tasks.filter { $0.status == .done || $0.status == .cancelled }
    }

    var body: some View {
        VStack(spacing: 0) {
            // mini tab
            HStack(spacing: 0) {
                taskTab(label: "进行中", count: activeTasks.count, active: !showArchived) {
                    showArchived = false
                }
                taskTab(label: "已完成", count: archivedTasks.count, active: showArchived) {
                    showArchived = true
                }
                Spacer()
                Button { state.showAddTaskOverlay = true } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("添加任务")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            let items = showArchived ? archivedTasks : activeTasks
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: showArchived ? "checkmark.circle" : "checklist")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text(showArchived ? "还没有已完成的任务" : "没有进行中的任务")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(items) { task in
                            TaskCard(task: task)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.automatic)
            }
        }
    }

    @ViewBuilder
    private func taskTab(label: String, count: Int, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: active ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(active ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15)))
                }
            }
            .foregroundStyle(active ? Color.accentColor : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(active ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 历史 Popover：带小标题

struct HistoryPopoverContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("历史")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)

            HistoryView()
        }
    }
}
