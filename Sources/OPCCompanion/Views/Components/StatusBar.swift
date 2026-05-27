import SwiftUI

/// 顶部状态条：左侧日期标题 + 右侧 popover 触发图标（任务 / 收件箱）。
/// 历史 / 设置 已升为顶部胶囊 Tab，不再走 popover。
/// 设计哲学：消息流专注纯粹对话，其他一切通过图标召唤为 popover。
struct StatusBar: View {
    @EnvironmentObject var state: AppState
    let activeTimerTitle: String?  // 进行中计时任务的标题，取代图标 badge 时显示

    var body: some View {
        // TimelineView 每秒刷新活跃计时剩余；wishSession 剩余也靠它
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            HStack(spacing: 10) {
                Text(dateTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                if let active = activeTimer {
                    statusDivider
                    activeBadge(active)
                }

                if let sess = state.wishClearingSession, !sess.expired {
                    statusDivider
                    wishBadge(sess)
                }

                Spacer(minLength: 4)

                StatusBarIcon(
                    tab: .tasks,
                    systemImage: AppTab.tasks.icon,
                    badgeCount: activeTaskCount,
                    isActive: state.selectedTab == .tasks,
                    action: { toggle(.tasks) }
                )
                StatusBarIcon(
                    tab: .inbox,
                    systemImage: AppTab.inbox.icon,
                    badgeCount: state.unreadNoteCount,
                    isActive: state.selectedTab == .inbox,
                    action: { toggle(.inbox) }
                )
                // 历史 / 设置 已升为顶部胶囊 Tab，不再放在 StatusBar
                // 设置入口：输入框敲 /设置 召唤，或点顶部胶囊
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .overlay(Divider().opacity(0.5), alignment: .bottom)
        }
    }

    private var statusDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 1, height: 10)
    }

    @ViewBuilder
    private func activeBadge(_ task: TaskItem) -> some View {
        let remaining = task.remainingSeconds ?? 0
        HStack(spacing: 4) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.taskInProgress)
            Text(task.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 140, alignment: .leading)
            Text(formatRemaining(remaining))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(remaining < 300 ? AppColors.statusError : .secondary)
        }
    }

    @ViewBuilder
    private func wishBadge(_ session: WishClearingSession) -> some View {
        let remainingMin = session.remainingSeconds / 60
        Button {
            state.endWishClearingSession()
            state.showBanner("已结束我想清扫", kind: .success, duration: 2.0)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                Text("我想清扫 · 剩 \(remainingMin) 分")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .opacity(0.6)
            }
            .foregroundStyle(.purple)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Color.purple.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .help("点击结束我想清扫")
    }

    private func formatRemaining(_ seconds: Int) -> String {
        let m = max(0, seconds) / 60
        let s = max(0, seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var activeTimer: TaskItem? {
        guard let t = state.activeTask, t.status == .inProgress else { return nil }
        return t
    }

    private var dateTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日 · EEEE"
        return f.string(from: Date())
    }

    private var activeTaskCount: Int {
        state.tasks.filter { $0.status == .pending || $0.status == .inProgress }.count
    }

    private func toggle(_ tab: AppTab) {
        withAnimation(AppAnimations.quick) {
            state.selectedTab = (state.selectedTab == tab) ? .chat : tab
        }
    }
}

struct StatusBarIcon: View {
    let tab: AppTab
    let systemImage: String
    let badgeCount: Int
    let isActive: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isActive ? Color.accentColor : (hovering ? Color.primary : Color.secondary))
                    .frame(width: 30, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isActive
                                  ? Color.accentColor.opacity(0.14)
                                  : (hovering ? Color.secondary.opacity(0.1) : Color.clear))
                    )
                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.red))
                        .offset(x: 6, y: -4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tab.title)
    }
}
