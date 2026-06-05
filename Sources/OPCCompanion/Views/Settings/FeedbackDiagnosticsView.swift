import SwiftUI
import AppKit

/// 设置页「版本与更新 + 反馈与诊断」区块。
/// - 更新：显示当前版本；有新版时给出说明 + 一键复制更新命令 / 打开主页；否则提供手动「检查更新」。
/// - 反馈：一键复制**已脱敏**的诊断日志 + 企微二维码（缺图则优雅隐藏）。
struct FeedbackDiagnosticsView: View {
    @EnvironmentObject var state: AppState
    @State private var checkingUpdate = false
    @State private var updateCheckResult = ""

    private let fallbackInstallCmd = "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Shiye-10Pages/OPC-Companion/refs/heads/feature/focused-conversation-memory/scripts/install.sh)\""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            updateBlock
            Divider()
            feedbackBlock
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.18), lineWidth: 1))
    }

    // MARK: - 更新

    @ViewBuilder
    private var updateBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("版本与更新").font(.headline)
                Spacer()
                Text("当前 v\(AppVersion.current)").font(.caption).foregroundColor(.secondary)
            }

            if let up = state.availableUpdate {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill").foregroundColor(.accentColor)
                    Text("有新版本 v\(up.version)").font(.subheadline).bold()
                }
                if !up.notes.isEmpty {
                    Text(up.notes).font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Button {
                        copyToClipboard(up.installCmd.isEmpty ? fallbackInstallCmd : up.installCmd, label: "更新命令")
                    } label: { Label("复制更新命令", systemImage: "doc.on.doc") }
                    .buttonStyle(.borderedProminent)

                    Button {
                        if let u = URL(string: up.url) { NSWorkspace.shared.open(u) }
                    } label: { Label("打开主页", systemImage: "arrow.up.right.square") }
                    .buttonStyle(.bordered)
                }
                Text("把命令粘贴到「终端」回车即可更新。").font(.caption2).foregroundColor(.secondary)
            } else {
                HStack(spacing: 8) {
                    Button {
                        checkingUpdate = true
                        updateCheckResult = ""
                        Task {
                            let r = await UpdateService.shared.checkNow()
                            await MainActor.run {
                                updateCheckResult = r
                                checkingUpdate = false
                            }
                        }
                    } label: { Label("检查更新", systemImage: "arrow.clockwise") }
                    .buttonStyle(.bordered)
                    .disabled(checkingUpdate)

                    if checkingUpdate { ProgressView().controlSize(.small) }
                    if !updateCheckResult.isEmpty {
                        Text(updateCheckResult).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 反馈与诊断

    @ViewBuilder
    private var feedbackBlock: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("反馈与诊断").font(.headline)
                Text("遇到问题？复制一份已脱敏的诊断日志发我，我来帮你看。日志不含 API Key、Notion Token，会议/随手记原文也已抹除。")
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    copyToClipboard(DiagnosticReport.build(), label: "诊断日志")
                } label: { Label("复制诊断日志", systemImage: "doc.on.clipboard") }
                .buttonStyle(.borderedProminent)

                Text("扫右侧二维码加我企微，把日志粘贴发我。").font(.caption2).foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            if let qr = AppBrand.wecomQRCodeImage() {
                VStack(spacing: 6) {
                    Image(nsImage: qr)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 132)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("扫码加我企微").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: -

    private func copyToClipboard(_ s: String, label: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        state.showBanner("已复制\(label)到剪贴板", kind: .success, duration: 2.0)
    }
}
