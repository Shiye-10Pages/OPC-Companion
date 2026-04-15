import SwiftUI

struct NotionConfirmCard: View {
    let action: NotionAction
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text")
                Text("即将执行 Notion 操作")
                    .font(.headline)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("操作：\(action.operation)")
                    .font(.subheadline)

                if !action.parameters.isEmpty {
                    Text("参数：")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(Array(action.parameters.keys.sorted()), id: \.self) { key in
                        if let value = action.parameters[key] {
                            HStack {
                                Text("\(key):")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(value)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }

            HStack {
                Button("取消") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("确认执行") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

@MainActor
final class NotionConfirmManager: ObservableObject {
    static let shared = NotionConfirmManager()

    @Published var pendingAction: NotionAction?
    @Published var showConfirmation = false

    private var onConfirmAction: (() -> Void)?
    private var onCancelAction: (() -> Void)?

    private init() {}

    func requestConfirmation(
        action: NotionAction,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.pendingAction = action
        self.onConfirmAction = onConfirm
        self.onCancelAction = onCancel
        self.showConfirmation = true
    }

    func confirm() {
        onConfirmAction?()
        clear()
    }

    func cancel() {
        onCancelAction?()
        clear()
    }

    private func clear() {
        pendingAction = nil
        onConfirmAction = nil
        onCancelAction = nil
        showConfirmation = false
    }
}