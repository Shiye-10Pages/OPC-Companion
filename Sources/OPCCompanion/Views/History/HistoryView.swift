import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Image(systemName: "clock")
                Text("对话历史")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if state.conversationHistory.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("暂无历史记录")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(state.conversationHistory) { day in
                        ConversationDayRow(day: day)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

struct ConversationDayRow: View {
    let day: ConversationDay
    @EnvironmentObject var state: AppState
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                    state.hasUnreadReminders = false
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(formattedDate(day.date))
                        .font(.headline)

                    Spacer()

                    Text("\(day.messages.count) 条消息")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(day.messages) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding(.leading, 24)
                .padding(.bottom, 8)
            }
        }
    }

    private func formattedDate(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"

        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "M月d日"

        if let date = inputFormatter.date(from: dateString) {
            let calendar = Calendar.current
            if calendar.isDateInToday(date) {
                return "今天"
            } else if calendar.isDateInYesterday(date) {
                return "昨天"
            }
            return outputFormatter.string(from: date)
        }
        return dateString
    }
}