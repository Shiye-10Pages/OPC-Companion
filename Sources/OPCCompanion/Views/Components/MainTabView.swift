import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedTab: AppTab = .chat

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .chat: ChatView()
                case .inbox: InboxView()
                case .history: HistoryView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .id(selectedTab)

            NewTabBar(selectedTab: $selectedTab) { tab in
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedTab = tab
                    state.selectedTab = tab
                }
            }
        }
        .onChange(of: state.selectedTab) { _, newValue in
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTab = newValue
            }
        }
    }
}

// 全宽 Tab 栏：底部横条 + Divider + 居中按钮组
struct NewTabBar: View {
    @Binding var selectedTab: AppTab
    let onSelect: (AppTab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 4) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    TabButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        action: { onSelect(tab) }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.regularMaterial)
    }
}

struct TabButton: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? tab.iconFilled : tab.icon)
                    .font(.system(size: 13, weight: .medium))
                Text(tab.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(isSelected ? .white : (hovering ? .primary : .secondary))
            .background(
                Capsule()
                    .fill(isSelected
                          ? AnyShapeStyle(AppColors.primaryGradient)
                          : AnyShapeStyle(hovering ? Color.secondary.opacity(0.12) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

extension AppTab {
    var iconFilled: String {
        switch self {
        case .chat: return "bubble.left.and.text.bubble.right.fill"
        case .inbox: return "tray.fill"
        case .history: return "clock.fill"
        case .settings: return "gearshape.fill"
        }
    }
}
