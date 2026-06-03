import SwiftUI

/// `/` 命令定义：输入 `/` 后弹出的候选列表
struct SlashCommand: Identifiable {
    let id: String
    let icon: String
    let label: String
    let description: String
    /// 选中后把输入框替换为此字符串（nil = 保持原样让用户继续输入，如随手记）
    let replacement: String?
    /// 执行命令；返回 true = 清空输入框，false = 保留
    let execute: (AppState) -> Bool

    @MainActor static let all: [SlashCommand] = [
        SlashCommand(id: "note", icon: "tray.and.arrow.down", label: "随手记", description: "/ 后跟内容直接存入收件箱", replacement: "/ ") { _ in false },
        SlashCommand(id: "chat", icon: "bubble.left.and.text.bubble.right", label: "聊聊", description: "清扫积压随手记（限时 10 分钟）", replacement: "/聊聊 ") { _ in false },
        SlashCommand(id: "ritual", icon: "sunrise.fill", label: "今日必做", description: "锁定今天要完成的 3 件事", replacement: nil) { state in
            state.showMorningRitual = true; return true
        },
        SlashCommand(id: "learn", icon: "brain.filled.head.profile", label: "学习", description: "审核近期的 [LEARN] 候选", replacement: nil) { state in
            state.triggerDreamingIfNeeded(); return true
        },
    ]

    @MainActor static func filtered(by query: String) -> [SlashCommand] {
        let q = query.lowercased()
        if q.isEmpty { return all }
        return all.filter {
            $0.label.lowercased().contains(q) ||
            $0.id.lowercased().contains(q) ||
            $0.description.lowercased().contains(q)
        }
    }
}

/// 输入框上方弹出的 `/` 命令补全菜单，支持上下键导航 + 回车选择
struct SlashCommandMenuView: View {
    let commands: [SlashCommand]
    let selectedIndex: Int
    let onSelect: (SlashCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(commands.enumerated()), id: \.element.id) { idx, cmd in
                Button {
                    onSelect(cmd)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: cmd.icon)
                            .font(.system(size: 12))
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 18)
                            .foregroundStyle(idx == selectedIndex ? Color.white : Color.accentColor)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(cmd.label)
                                .font(.system(size: 12, weight: .medium))
                            Text(cmd.description)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(idx == selectedIndex ? Color.accentColor : Color.clear)
                    )
                    .foregroundStyle(idx == selectedIndex ? .white : .primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .glassBackground(cornerRadius: 10)
    }
}
