import SwiftUI

struct InboxView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedNoteIds: Set<UUID> = []

    private var visibleNotes: [Note] {
        state.notes.filter { $0.status != .deleted }
    }

    private var pendingNotes: [Note] {
        state.notes.filter { $0.status == .pending }
    }

    private var grouped: [(date: String, notes: [Note])] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let groups = Dictionary(grouping: visibleNotes) { df.string(from: $0.capturedAt) }
        return groups
            .map { (date: $0.key, notes: $0.value.sorted { $0.capturedAt > $1.capturedAt }) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "tray")
                Text("收件箱").font(.headline)
                Spacer()
                if state.unreadNoteCount > 0 {
                    Text("\(state.unreadNoteCount) 条未处理")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if visibleNotes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(grouped, id: \.date) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(formatDateHeader(group.date))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 16)

                                VStack(spacing: 6) {
                                    ForEach(group.notes) { note in
                                        NoteCard(
                                            note: note,
                                            isSelected: selectedNoteIds.contains(note.id),
                                            toggleSelected: { toggleSelection(note) }
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
                bottomActionBar
            }
        }
    }

    @ViewBuilder
    private var bottomActionBar: some View {
        let pendingCount = pendingNotes.count
        let selectedCount = selectedNoteIds.count
        if pendingCount > 0 || selectedCount > 0 {
            HStack {
                if selectedCount > 0 {
                    Text("已选 \(selectedCount) 条").font(.caption).foregroundColor(.secondary)
                    Button("批量推 Notion") { batchPushNotion() }
                        .buttonStyle(.bordered)
                    Button("清除选择") {
                        selectedNoteIds.removeAll()
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                } else {
                    Spacer()
                    Button {
                        organize()
                    } label: {
                        if state.isOrganizing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("一键整理", systemImage: "wand.and.stars")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isOrganizing || pendingCount == 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Rectangle()
                    .fill(.regularMaterial)
                    .overlay(Divider(), alignment: .top)
            )
        }
    }

    private func toggleSelection(_ note: Note) {
        if selectedNoteIds.contains(note.id) {
            selectedNoteIds.remove(note.id)
        } else {
            selectedNoteIds.insert(note.id)
        }
    }

    private func organize() {
        Task { await state.organizePendingNotes() }
    }

    private func batchPushNotion() {
        let snapshot = selectedNoteIds
        Task {
            var failed: Set<UUID> = []
            for id in snapshot {
                guard let note = state.notes.first(where: { $0.id == id && $0.status == .pending }) else {
                    continue
                }
                let ok = await state.pushNoteToNotion(note)
                if !ok { failed.insert(id) }
            }
            await MainActor.run {
                // 仅保留失败的，方便用户一键重试
                selectedNoteIds = failed
                if failed.isEmpty {
                    state.appendMessage(Message(role: .system, content: "✓ 批量推送完成（共 \(snapshot.count) 条）"))
                } else {
                    state.appendMessage(Message(role: .system, content: "⚠️ \(failed.count)/\(snapshot.count) 条推送失败，已保留选中可重试"))
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("还没有随手记")
                .foregroundColor(.secondary)
            Text("按 Option + ` 快速捕获，或在对话框以 / 开头")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatDateHeader(_ dateString: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        guard let date = df.date(from: dateString) else { return dateString }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "💡 今天" }
        if cal.isDateInYesterday(date) { return "💡 昨天" }
        df.dateFormat = "M月d日"
        return "💡 " + df.string(from: date)
    }
}

struct NoteCard: View {
    let note: Note
    let isSelected: Bool
    let toggleSelected: () -> Void
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if note.status == .pending {
                Button(action: toggleSelected) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(note.content)
                    .font(.system(size: 13))
                    .strikethrough(note.status == .done)
                    .foregroundColor(note.status == .done ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text(formatTime(note.capturedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    actionButtons
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.card)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.card)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var actionButtons: some View {
        if note.status == .pending {
            HStack(spacing: 10) {
                Button("完成") { state.markNoteDone(note) }
                Button("转任务") { state.convertNoteToTask(note) }
                Button("推 Notion") { pushNotion() }
                Button("删除") { state.deleteNote(note) }
                    .foregroundColor(.red)
            }
            .font(.caption)
            .buttonStyle(.borderless)
        } else {
            Text("已处理")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: date)
    }

    private func pushNotion() {
        Task { await state.pushNoteToNotion(note) }
    }
}
