import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedTab: AppTab = .chat

    var body: some View {
        VStack(spacing: 0) {
            // Tab 内容
            Group {
                switch selectedTab {
                case .chat:
                    ChatView()
                case .history:
                    HistoryView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Tab 栏 - 新设计
            NewTabBar(selectedTab: $selectedTab) { tab in
                withAnimation(AppAnimations.smooth) {
                    selectedTab = tab
                    state.selectedTab = tab
                }
            }
        }
        .onChange(of: state.selectedTab) { _, newValue in
            selectedTab = newValue
        }
    }
}

// MARK: - 新 Tab 栏设计
struct NewTabBar: View {
    @Binding var selectedTab: AppTab
    let onSelect: (AppTab) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                TabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    action: { onSelect(tab) }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
    }
}

struct TabButton: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? tab.iconFilled : tab.icon)
                    .font(.system(size: 14, weight: .medium))

                Text(tab.title)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundColor(isSelected ? .white : .secondary)
            .background(
                Capsule()
                    .fill(isSelected ? AnyShapeStyle(AppColors.primaryGradient) : AnyShapeStyle(Color.clear))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AppTab 扩展（添加 iconFilled）
extension AppTab {
    var iconFilled: String {
        switch self {
        case .chat: return "bubble.left.and.text.bubble.right.fill"
        case .history: return "clock.fill"
        case .settings: return "gearshape.fill"
        }
    }
}