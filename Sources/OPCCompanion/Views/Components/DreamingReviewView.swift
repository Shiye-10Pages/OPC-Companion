import SwiftUI

/// Dreaming 候选审核浮层：列出最近 7 天 [LEARN] 候选条目，用户逐条 approve / reject。
struct DreamingReviewView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "brain.filled.head.profile")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(nsColor: .systemPurple))
                Text("学到的东西要记下来吗？")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    state.markDreamingReviewDone()
                } label: {
                    Text("全部跳过")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(state.pendingLearnings, id: \.id) { item in
                        candidateRow(itemId: item.id, date: item.date, entry: item.entry)
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .padding(16)
        .frame(width: 420)
        .glassBackground()
    }

    @ViewBuilder
    private func candidateRow(itemId: UUID, date: String, entry: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(date)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                HoverIconButton(systemImage: "checkmark.circle.fill", help: "记住") {
                    DreamingService.shared.promote(entry: entry)
                    state.pendingLearnings.removeAll { $0.id == itemId }
                    state.showBanner("已记入长期记忆", kind: .success, duration: 2.0)
                    if state.pendingLearnings.isEmpty { state.showDreamingReview = false }
                }
                HoverIconButton(systemImage: "xmark.circle", help: "丢弃") {
                    state.pendingLearnings.removeAll { $0.id == itemId }
                    if state.pendingLearnings.isEmpty { state.showDreamingReview = false }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
    }
}
