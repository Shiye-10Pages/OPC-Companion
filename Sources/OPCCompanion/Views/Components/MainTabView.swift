import SwiftUI
import AppKit

struct MainTabView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme

    /// Quiet Field 的当前可见场所：此刻 / 浮念 / 收束 / 设置。
    /// state.selectedTab 仍保留 5 个 case，.tasks 作为此刻上的 popover 触发态。
    @State private var visibleTab: AppTab = .chat

    /// 可见的三颗场所胶囊（顺序固定）
    private static let visibleTabs: [AppTab] = [.chat, .inbox, .history]

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // —— 顶部场所导航（始终常驻）——
                // 拖动热区由 AppDelegate.setupDragHotZoneMonitor() 在 AppKit 事件路径上处理。
                // 在 SwiftUI 里包 NSView+mouseDownCanMoveWindow 完全不工作：NSHostingView 会
                // 吞掉鼠标事件，AppKit 检查 mouseDownCanMoveWindow 的代码路径根本走不到。
                HStack(spacing: 10) {
                    Spacer()
                    NewTabBar(visibleTab: visibleTab, tabs: Self.visibleTabs) { tab in
                        selectVisibleTab(tab)
                    }
                    SettingsGearButton(isSelected: visibleTab == .settings) {
                        selectSettings()
                    }
                    Spacer()
                }
                .padding(.top, 12)
                .padding(.bottom, 14)   // 拉开与 StatusBar 的呼吸距离，避免双重背景硬边
                .frame(maxWidth: .infinity)

                // —— 内容区：按可见场所切换 ——
                Group {
                    switch visibleTab {
                    case .chat:
                        momentStack
                    case .inbox:
                        FloatingThoughtsScene()
                    case .history:
                        ClosureScene()
                    case .settings:
                        SettingsView()
                    default:
                        momentStack
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }

            // —— 仅任务保留为 popover；浮念已升为主场所 ——
            if visibleTab == .chat {
                if state.selectedTab == .tasks {
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
                if state.showDreamingReview && !state.pendingLearnings.isEmpty {
                    dreamingReviewOverlay
                }
            }

            if state.showScheduledTaskForm {
                scheduledTaskFormOverlay
            }
        }
        .animation(AppAnimations.smooth, value: visibleTab)
        .animation(AppAnimations.quick, value: state.selectedTab)
        .animation(AppAnimations.quick, value: state.showAddTaskOverlay)
        .animation(AppAnimations.standard, value: state.showProgressPingPanel)
        .animation(AppAnimations.quick, value: state.showMorningRitual)
        .animation(AppAnimations.quick, value: state.nextCandidates.count)
        .animation(AppAnimations.quick, value: state.postMortemQueue.count)
        .animation(AppAnimations.quick, value: state.showDreamingReview)
        .onAppear { syncVisibleTab(from: state.selectedTab) }
        .onChange(of: state.selectedTab) { _, newValue in
            // 外部代码（AppDelegate / 槽位命令 / openInbox）设置 selectedTab 时：
            // chat/inbox/history/settings 切换可见场所；tasks 保留为此刻上的 popover。
            syncVisibleTab(from: newValue)
        }
    }

    // MARK: - 可见 tab 同步

    private func selectVisibleTab(_ tab: AppTab) {
        guard Self.visibleTabs.contains(tab) else { return }
        withAnimation(AppAnimations.smooth) {
            visibleTab = tab
            state.selectedTab = tab
        }
    }

    private func selectSettings() {
        withAnimation(AppAnimations.smooth) {
            visibleTab = .settings
            state.selectedTab = .settings
        }
    }

    private func syncVisibleTab(from selected: AppTab) {
        switch selected {
        case .chat, .inbox, .history, .settings:
            if visibleTab != selected {
                withAnimation(AppAnimations.smooth) {
                    visibleTab = selected
                }
            }
        case .tasks:
            // 显示任务 popover 的同时确保底层在此刻
            if visibleTab != .chat {
                withAnimation(AppAnimations.smooth) {
                    visibleTab = .chat
                }
            }
        }
    }

    // MARK: - 此刻内容栈（StatusBar + 状态面板 + ProgressPing + ChatView）

    private var momentStack: some View {
        VStack(spacing: 0) {
            StatusBar(activeTimerTitle: state.activeTask?.title)

            if state.wishClearingSession != nil {
                QuietWishClearingDesk()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                QuietMomentDashboard()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

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
    }

    // MARK: - Overlay 们（保持原行为）

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
                default: EmptyView()
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

// MARK: - Quiet Field 场所导航（此刻 / 浮念 / 收束）

struct NewTabBar: View {
    let visibleTab: AppTab
    let tabs: [AppTab]
    let onSelect: (AppTab) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { tab in
                TabButton(
                    tab: tab,
                    isSelected: visibleTab == tab,
                    action: { onSelect(tab) }
                )
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .opacity(0.55)
        )
        .overlay(
            Capsule()
                .stroke(theme.textTertiary.opacity(0.25), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 2)
    }
}

struct TabButton: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.fontStyle) private var fontStyle

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? tab.iconFilled : tab.icon)
                    .font(.system(size: 13, weight: .medium))
                Text(tab.title)
                    .font(fontStyle.titleFont)
                    .tracking(isSelected ? 0.04 : 0.06)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(minHeight: 32)              // 保证热区不小于 32pt
            .contentShape(Capsule())            // 整个胶囊区可点
            .foregroundStyle(isSelected ? Color.white : theme.textSecondary)
            .background(
                Capsule()
                    .fill(isSelected
                          ? AnyShapeStyle(theme.bubbleUserStyle)
                          : AnyShapeStyle(Color.clear))
            )
            .shadow(color: isSelected ? theme.accent.opacity(0.30) : .clear,
                    radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct SettingsGearButton: View {
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isSelected ? "gearshape.fill" : "gearshape")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : (hovering ? theme.textPrimary : theme.textSecondary))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(isSelected
                              ? AnyShapeStyle(theme.bubbleUserStyle)
                              : AnyShapeStyle(hovering ? theme.textTertiary.opacity(0.12) : Color.clear))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("设置")
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.18), value: hovering)
        .animation(.easeOut(duration: 0.22), value: isSelected)
    }
}

// MARK: - AppTab 扩展（填充图标，仅胶囊用）

extension AppTab {
    var iconFilled: String {
        switch self {
        case .chat: return "dot.circle.fill"
        case .tasks: return "checklist"
        case .inbox: return "tray.fill"
        case .history: return "checkmark.seal.fill"
        case .settings: return "gearshape.fill"
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
            .sorted { ($0.status == .inProgress ? 0 : 1) < ($1.status == .inProgress ? 0 : 1) }
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

// 拖动热区：见 AppDelegate.setupDragHotZoneMonitor()。
// 历史上这里有 WindowDragHandle (NSViewRepresentable + mouseDownCanMoveWindow=true)。
// 实测在 NSHostingView 包裹下完全失效——SwiftUI 自己 hit-test 把鼠标事件消化掉了，
// AppKit 检查 mouseDownCanMoveWindow 的代码路径根本走不到，所以面板完全不能拖。
// 已迁移到 AppDelegate 的 NSEvent.addLocalMonitorForEvents 方案。
