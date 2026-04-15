import SwiftUI

struct StatusBarPopoverView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            // 状态栏
            HStack {
                Image(systemName: "bubble.left.fill")
                    .foregroundColor(AppColors.primary)
                Text("OPC 伴侣")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(getCurrentTime())
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            // 简易对话/状态展示区
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // 任务状态
                    if !state.tasks.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("\(state.tasks.count) 个任务")
                                .font(.system(size: 13))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }

                    // 未读提醒
                    if state.hasUnreadReminders {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.orange)
                            Text("有待处理提醒")
                                .font(.system(size: 13))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }

                    // 当前任务
                    if let activeTask = state.activeTask {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(AppColors.primary)
                            VStack(alignment: .leading) {
                                Text(activeTask.title)
                                    .font(.system(size: 13))
                                if let remaining = activeTask.remainingSeconds {
                                    Text(formatTime(remaining))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(remaining < 300 ? .red : .secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }

            Divider()

            // 底部操作
            HStack(spacing: 12) {
                Button(action: {
                    print("[Popover] 打开面板 pressed")
                    if let delegate = AppDelegate.shared {
                        delegate.popover?.close()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            delegate.showPanel()
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.expand.vertical")
                        Text("打开面板")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: {
                    print("[Popover] 设置 pressed")
                    if let delegate = AppDelegate.shared {
                        delegate.popover?.close()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            delegate.showPanel()
                            self.state.selectedTab = .settings
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                        Text("设置")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    print("[Popover] 退出 pressed")
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 320, height: 200)
    }

    private func getCurrentTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// 预览
struct StatusBarPopoverView_Previews: PreviewProvider {
    static var previews: some View {
        StatusBarPopoverView()
            .environmentObject(AppState.shared)
    }
}