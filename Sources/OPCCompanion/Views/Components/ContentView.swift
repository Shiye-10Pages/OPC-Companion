import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var themeProvider = ThemeProvider.shared
    @State private var bgVisible = false
    @State private var streamVisible = false
    @State private var burstID = 0

    var body: some View {
        ZStack {
            themeProvider.current.background
                .opacity(bgVisible ? 1 : 0)
                .blur(radius: bgVisible ? 0 : 20)
                .clipShape(RoundedRectangle(cornerRadius: themeProvider.current.panelCornerRadius))

            if bgVisible {
                BurstFlash(accent: themeProvider.current.accent)
                    .id(burstID)
                    .clipShape(RoundedRectangle(cornerRadius: themeProvider.current.panelCornerRadius))
                    .allowsHitTesting(false)
            }

            MainTabView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(streamVisible ? 1 : 0)
                .offset(y: streamVisible ? 0 : 8)

            PanelWatermark()
                .opacity(bgVisible ? 0.9 : 0)
        }
        .frame(width: 760, height: 620)
        .clipShape(RoundedRectangle(cornerRadius: themeProvider.current.panelCornerRadius))
        .environment(\.theme, themeProvider.current)
        .overlay(alignment: .top) {
            if let banner = state.banner {
                BannerView(message: banner)
                    .padding(.horizontal, 16)
                    .padding(.top, 48)  // 让出顶部 StatusBar（高约 42pt），避免盖住活跃计时/图标
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(banner.id)
            }
        }
        .animation(AppAnimations.smooth, value: state.banner?.id)
        .onAppear { playEntrance() }
        .onChange(of: state.isPanelVisible) { _, visible in
            if visible { playEntrance() }
        }
        // 注：themeID 变更由 ThemeProvider.bind() 内部通过 AppState.$config 订阅自动同步，
        // 这里不再手动 update，避免双触发与未来死代码。
    }

    private func playEntrance() {
        bgVisible = false
        streamVisible = false
        burstID += 1

        withAnimation(.easeOut(duration: 0.5)) {
            bgVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeOut(duration: 0.45)) {
                streamVisible = true
            }
        }
    }
}

private struct PanelWatermark: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        VStack {
            Spacer()
            HStack {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color(hex: "#4ED8C0"))
                        .frame(width: 4, height: 4)
                        .shadow(color: Color(hex: "#4ED8C0").opacity(0.85), radius: 3)
                    Text("OPC · SOUL · ONLINE")
                }
                Spacer()
                Text("SN · 760x620 · \(state.config.themeID.uppercased())")
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(theme.textTertiary)
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
            .allowsHitTesting(false)
        }
    }
}
