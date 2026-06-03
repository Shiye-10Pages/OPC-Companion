import SwiftUI

/// Quiet Field 折叠前门 bar（收敛方案 B）。
///
/// 只负责折叠态：一行输入记随手记（本地、不走 AI）+「聊聊」展开进清扫 + ⌄ 展开。
/// 「展开」不再卷帘，而是切到 classic 完整主面板（AppDelegate.expandToMainPanel）。
/// 主动介入（复盘 / 学习 / 下一件）统一在主面板显示，折叠 bar 不挂。
struct QuietFieldShell: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme

    @State private var appeared = false
    @State private var inputText = ""
    @State private var captured = false
    @FocusState private var inputFocused: Bool

    private let cardWidth: CGFloat = 524

    var body: some View {
        card
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 16)
            .onAppear {
                focusSoon()
                withAnimation(theme.panelEntrance) { appeared = true }
            }
    }

    // MARK: - 折叠 bar 卡片

    private var card: some View {
        inputRegion
            .frame(width: cardWidth)
            .background(
                // GeometryReader 把毛玻璃焊死在卡片尺寸内，圆角裁切兜底。
                GeometryReader { geo in
                    Rectangle().fill(.regularMaterial)
                        .frame(width: geo.size.width, height: geo.size.height)
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
            .animation(AppAnimations.smooth, value: state.banner?.id)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - 输入区（单行 pill + 聊聊 / 展开两个入口）

    private var inputRegion: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 15))
                .foregroundStyle(theme.textSecondary)

            TextField("记一下想法…", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($inputFocused)
                .onSubmit(handleSubmit)

            // 折叠 bar 只记随手记；「聊聊」= 展开进清扫；⌄ = 展开到完整主面板。
            clearingChip

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

    /// 「聊聊」入口：展开并进入清扫（聊聊 = 限时清扫积压随手记）。
    private var clearingChip: some View {
        Button { enterClearing() } label: {
            Text("聊聊")
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(theme.accent.opacity(0.18)))
                .foregroundStyle(theme.accent)
        }
        .buttonStyle(.plain)
        .help("聊聊：限时清扫积压的随手记")
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

    // MARK: - 行为

    /// 折叠 = 记随手记：本地接住，不走 AI；闪一下"已接住"，随即关闭。
    private func handleSubmit() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard state.captureNote(content: trimmed, source: .hotkeyText, inputMode: .text) else { return }
        inputText = ""
        withAnimation(AppAnimations.quick) { captured = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            AppDelegate.shared?.hideQuietFieldPreview()
        }
    }

    /// ⌄ 展开 → 切到 classic 完整主面板。
    private func expand() {
        AppDelegate.shared?.expandToMainPanel()
    }

    /// 「聊聊」→ 开启清扫会话 + 切到完整主面板（momentStack 会显示清扫桌）。
    private func enterClearing() {
        let anchor = activeTask?.title ?? pendingTasks.first?.title
        state.startWishClearingSession(anchorTask: anchor)
        state.wishClearingFocusNoteID = state.wishClearingCandidates.first?.id
        AppDelegate.shared?.expandToMainPanel()
    }

    private func focusSoon() {
        DispatchQueue.main.async { inputFocused = true }
    }

    // MARK: - 派生状态（enterClearing 锚点用）

    private var activeTask: TaskItem? {
        guard let a = state.activeTask, a.status == .inProgress else { return nil }
        return a
    }
    private var pendingTasks: [TaskItem] { state.tasks.filter { $0.status == .pending } }
}
