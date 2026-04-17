import SwiftUI

/// 顶部状态条：左侧日期标题 + 右侧 4 个 popover 触发图标（任务 / 收件箱 / 历史 / 设置）。
/// 设计哲学：消息流专注纯粹对话，其他一切通过图标召唤为 popover。
struct StatusBar: View {
    @EnvironmentObject var state: AppState
    let activeTimerTitle: String?  // 进行中计时任务的标题，取代图标 badge 时显示

    var body: some View {
        HStack(spacing: 10) {
            Text(dateTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

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
            StatusBarIcon(
                tab: .history,
                systemImage: AppTab.history.icon,
                badgeCount: 0,
                isActive: state.selectedTab == .history,
                action: { toggle(.history) }
            )
            // 设置图标已移除；输入框敲 /设置 召唤
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(Divider().opacity(0.5), alignment: .bottom)
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
