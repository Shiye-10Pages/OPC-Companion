import SwiftUI

struct AboutShiyeAIView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("关于十页AI")
                    .font(.headline)

                Text("十页AI打造")
                    .font(.system(size: 18, weight: .semibold))

                Text("一个用 AI 做梦的男人。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("想看十页AI如何使用 AI？")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    AppBrand.openResources()
                } label: {
                    Label("更多 AI 资源", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderedProminent)

                Text("小红书：naiyoubaba")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            if let image = AppBrand.xiaohongshuQRCodeImage() {
                VStack(spacing: 6) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 132)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("扫码在小红书找到我")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }
}
