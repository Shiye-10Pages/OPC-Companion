import SwiftUI

struct BannerView: View {
    let message: BannerMessage
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tintColor)
                .symbolRenderingMode(.hierarchical)

            Text(message.text)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            if let action = message.action {
                Button(actionLabel(action)) {
                    state.handleBannerAction(action)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 520, alignment: .leading)
        .glassBackground(cornerRadius: 10)
    }

    private var iconName: String {
        switch message.kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var tintColor: Color {
        switch message.kind {
        case .info: return Color(nsColor: .systemBlue)
        case .success: return Color(nsColor: .systemGreen)
        case .warning: return Color(nsColor: .systemOrange)
        case .error: return Color(nsColor: .systemRed)
        }
    }

    private func actionLabel(_ action: BannerMessage.Action) -> String {
        switch action {
        case .openMorningRitual: return "立刻做"
        case .undoBatchDelete: return "撤销"
        }
    }
}
