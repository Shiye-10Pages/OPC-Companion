import SwiftUI

/// 统一的操作按钮。macOS 26 风格：用 `.bordered` 让系统管 hover 效果 + `.symbolRenderingMode(.hierarchical)` 给图标层次感。
struct HoverIconButton: View {
    let systemImage: String?
    let label: String?
    let help: String
    let action: () -> Void

    init(systemImage: String? = nil, label: String? = nil, help: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let label {
                    Text(label)
                        .font(.caption)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12))
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .frame(minWidth: 24, minHeight: 24)
            .padding(.horizontal, label == nil ? 0 : 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.secondary)
        .help(help)
    }
}
