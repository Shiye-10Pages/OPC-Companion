import SwiftUI

struct InboxView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedNoteIds: Set<UUID> = []
    @State private var showProcessed = false

    private var pendingNotes: [Note] {
        state.notes.filter { $0.status == .pending || $0.status == .expired }
    }

    private var processedNotes: [Note] {
        state.notes.filter { $0.status == .done }
    }

    private var activeNotes: [Note] {
        showProcessed ? processedNotes : pendingNotes
    }

    private var grouped: [(date: String, notes: [Note])] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let groups = Dictionary(grouping: activeNotes) { df.string(from: $0.capturedAt) }
        return groups
            .map { (date: $0.key, notes: $0.value.sorted { $0.capturedAt > $1.capturedAt }) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部 mini tab：待处理 / 已处理
            HStack(spacing: 0) {
                inboxTab(label: "待处理", count: pendingNotes.count, active: !showProcessed) {
                    showProcessed = false
                    selectedNoteIds.removeAll()
                }
                inboxTab(label: "已处理", count: processedNotes.count, active: showProcessed) {
                    showProcessed = true
                    selectedNoteIds.removeAll()
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if activeNotes.isEmpty {
                if showProcessed {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("没有已处理的记录")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyState
                }
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
            VStack(spacing: 0) {
                Divider().opacity(0.5)
                HStack(spacing: 8) {
                    // 全选 / 取消全选
                    Button {
                        if selectedNoteIds.count == pendingNotes.count {
                            selectedNoteIds.removeAll()
                        } else {
                            selectedNoteIds = Set(pendingNotes.map { $0.id })
                        }
                    } label: {
                        Text(selectedNoteIds.count == pendingNotes.count && !pendingNotes.isEmpty ? "取消全选" : "全选")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if selectedCount > 0 {
                        Text("已选 \(selectedCount)").font(.caption).foregroundColor(.secondary)

                        Spacer()

                        HoverIconButton(systemImage: "checkmark.circle", help: "批量完成") {
                            batchMarkDone()
                        }
                        HoverIconButton(systemImage: "trash", help: "批量删除") {
                            batchDelete()
                        }
                        HoverIconButton(label: "Notion", help: "批量推送") {
                            batchPushNotion()
                        }
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
                        .controlSize(.small)
                        .disabled(state.isOrganizing || pendingCount == 0)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func batchMarkDone() {
        for id in selectedNoteIds {
            if let note = state.notes.first(where: { $0.id == id && $0.status == .pending }) {
                state.markNoteDone(note)
            }
        }
        let count = selectedNoteIds.count
        selectedNoteIds.removeAll()
        state.showBanner("已完成 \(count) 条", kind: .success)
    }

    private func batchDelete() {
        let ids = selectedNoteIds
        guard !ids.isEmpty else { return }
        // ≥3 条时原生 NSAlert 二次确认；<3 条跳过确认直接删（删多了有 banner 撤销兜底）
        if ids.count >= 3 {
            let alert = NSAlert()
            alert.messageText = "删除 \(ids.count) 条随手记？"
            alert.informativeText = "5 秒内可从顶部 banner 撤销"
            alert.addButton(withTitle: "删除")
            alert.addButton(withTitle: "取消")
            alert.alertStyle = .warning
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        state.batchDeleteNotesWithUndo(ids: ids)
        selectedNoteIds.removeAll()
    }

    @ViewBuilder
    private func inboxTab(label: String, count: Int, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: active ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(active ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15))
                        )
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
                    state.showBanner("批量推送完成（共 \(snapshot.count) 条）", kind: .success)
                } else {
                    state.showBanner("\(failed.count)/\(snapshot.count) 条推送失败，已保留选中可重试", kind: .warning, duration: 5.0)
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
                HStack(alignment: .top, spacing: 6) {
                    if note.kind == .wish {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .semibold))
                            Text("我想")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.purple.opacity(0.15))
                        )
                        .foregroundColor(.purple)
                    }
                    Text(note.content)
                        .font(.system(size: 13))
                        .strikethrough(note.status == .done || note.status == .expired)
                        .foregroundColor(note.status == .pending ? .primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 6) {
                    Text(formatTime(note.capturedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if note.status == .expired {
                        Text("· 已过期")
                            .font(.caption)
                            .foregroundColor(Color(nsColor: .systemOrange))
                    }
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
        switch note.status {
        case .pending:
            HStack(spacing: 2) {
                HoverIconButton(systemImage: "bubble.left.and.text.bubble.right", help: "聊聊这条（进入我想清扫）") { chatAboutNote() }
                HoverIconButton(systemImage: "checkmark.circle", help: "标记完成") { state.markNoteDone(note) }
                HoverIconButton(systemImage: "arrow.right.circle", help: "转任务") { state.convertNoteToTask(note) }
                HoverIconButton(label: "Notion", help: "推送到 Notion") { pushNotion() }
                HoverIconButton(systemImage: "trash", help: "删除") { state.deleteNote(note) }
            }
        case .expired:
            HStack(spacing: 2) {
                HoverIconButton(systemImage: "bubble.left.and.text.bubble.right", help: "聊聊这条（进入我想清扫）") { chatAboutNote() }
                HoverIconButton(systemImage: "arrow.right.circle", help: "转任务") { state.convertNoteToTask(note) }
                HoverIconButton(systemImage: "trash", help: "删除") { state.deleteNote(note) }
            }
        default:
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

    private func chatAboutNote() {
        state.dispatchWishChat(noteId: note.id)
    }
}
