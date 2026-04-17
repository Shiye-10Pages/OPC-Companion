import SwiftUI

struct BannerView: View {
    let message: BannerMessage

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
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
}
