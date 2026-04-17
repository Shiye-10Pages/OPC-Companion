import SwiftUI

/// 任务完成后弹出的"下一个"浮层：从 pending 列表挑 3 个候选，一键启动。
struct NextCandidatesView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                Text("下一个？")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    state.nextCandidates = []
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }

            VStack(spacing: 6) {
                ForEach(state.nextCandidates) { task in
                    candidateRow(task)
                }
            }

            HStack {
                Spacer()
                Button("都不做") {
                    state.nextCandidates = []
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(width: 340)
        .glassBackground(cornerRadius: AppCornerRadius.card)
    }

    @ViewBuilder
    private func candidateRow(_ task: TaskItem) -> some View {
        Button {
            // 原地升级 pending → inProgress，保留 createdAt 等元数据
            if let idx = state.tasks.firstIndex(where: { $0.id == task.id }) {
                let m = task.timerMinutes ?? 25
                state.tasks[idx].status = .inProgress
                state.tasks[idx].timerMinutes = m
                state.tasks[idx].timerStart = Date()
                state.tasks[idx].timerEnd = Date().addingTimeInterval(TimeInterval(m * 60))
                state.activeTask = state.tasks[idx]
                state.menuBarStatus = .focus
                state.resetTimerFlags()
                state.lastProgressPingAt = Date()
                state.saveTasks()
                state.showBanner("已启动：\(task.title) · \(m) 分钟", kind: .success)
                MemoryService.shared.appendToToday(.tasks, entry: "启动计时：\(task.title) · \(m) 分钟")
            }
            state.nextCandidates = []
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 14))
                Text(task.title)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                if let m = task.timerMinutes {
                    Text("\(m)m")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
