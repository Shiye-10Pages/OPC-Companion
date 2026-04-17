import SwiftUI

struct QuickCaptureView: View {
    let autoStartVoice: Bool
    let onSubmit: (String, InputMode) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @State private var voiceMode = false
    @State private var pulse = false
    @FocusState private var isFocused: Bool
    @ObservedObject private var voice = VoiceService.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: voiceMode ? "mic.fill" : "tray.and.arrow.down")
                .font(.system(size: 16))
                .foregroundColor(voiceMode ? .red : .secondary)
                .scaleEffect(voiceMode && pulse ? 1.15 : 1.0)
                .animation(
                    voiceMode ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default,
                    value: pulse
                )

            TextField(voiceMode ? "正在听你说..." : "记一下想法...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isFocused)
                .onSubmit { submit() }

            Button { submit() } label: {
                let isEmpty = text.trimmingCharacters(in: .whitespaces).isEmpty
                ZStack {
                    Circle()
                        .fill(isEmpty
                              ? AnyShapeStyle(Color.secondary.opacity(0.15))
                              : AnyShapeStyle(Color.accentColor))
                    Image(systemName: "return.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isEmpty ? .secondary : .white)
                }
                .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isFocused ? AppColors.primary.opacity(0.6) : Color.clear,
                    lineWidth: 1.5
                )
        )
        .onAppear {
            isFocused = true
            if autoStartVoice {
                startVoice()
            }
        }
        .onDisappear {
            stopVoiceIfNeeded()
        }
        .onChange(of: voice.transcript) { _, newValue in
            // 仅在语音模式下用转写覆盖文字框
            if voiceMode && !newValue.isEmpty {
                text = newValue
            }
        }
        .onChange(of: text) { _, newValue in
            // 语音模式下用户敲键（text 与 transcript 不一致）→ 切到文字模式
            if voiceMode && newValue != voice.transcript {
                stopVoiceIfNeeded()
                voiceMode = false
            }
        }
    }

    private func startVoice() {
        Task {
            let authorized = await voice.requestAuthorization()
            guard authorized else { return }
            do {
                try voice.startRecording()
                await MainActor.run {
                    voiceMode = true
                    pulse = true
                }
            } catch {
                // 录音失败 fallback 到文字模式
            }
        }
    }

    private func stopVoiceIfNeeded() {
        if voice.isRecording {
            voice.stopRecording()
        }
        pulse = false
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let mode: InputMode = voiceMode ? .voice : .text
        stopVoiceIfNeeded()
        onSubmit(trimmed, mode)
        text = ""
    }
}
