import SwiftUI
import AppKit

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
        }
        .frame(width: 760, height: 620)
        .environment(\.theme, themeProvider.current)
        .environment(\.fontStyle, FontStyleSet.from(
            FontStyleID(rawValue: state.config.fontStyleID) ?? .readable
        ))
        .preferredColorScheme(
            (ColorSchemeOverride(rawValue: state.config.colorSchemeOverride) ?? .system).resolved
        )
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
        .onAppear {
            playEntrance()
            syncPanelCornerRadius()
            syncPanelAppearance()
        }
        .onChange(of: state.isPanelVisible) { _, visible in
            if visible { playEntrance() }
        }
        // 注：themeID 变更由 ThemeProvider.bind() 内部通过 AppState.$config 订阅自动同步，
        // 这里仅在主题切换时把 visualEffectView 的圆角同步到主题值，避免 effectView 16
        // 跟 SwiftUI 26/4 不一致导致「圆角内有圆角 / 锐角」。
        .onChange(of: themeProvider.current.id) { _, _ in
            syncPanelCornerRadius()
        }
        // 颜色方案切换：SwiftUI .preferredColorScheme 只影响 view tree，NSPanel 的
        // visualEffectView 走自己的 appearance 系统。这里手动同步 panel.appearance。
        .onChange(of: state.config.colorSchemeOverride) { _, _ in
            syncPanelAppearance()
        }
    }

    private func syncPanelCornerRadius() {
        let r = themeProvider.current.panelCornerRadius
        guard let effectView = AppDelegate.shared?.panelEffectView else { return }
        // 1. effectView 的 maskImage（关键：material 的 backdrop 只听这个）
        effectView.maskImage = AppDelegate.makeRoundedMaskImage(cornerRadius: r)
        // 2. effectView layer cornerRadius（普通 layer 内容裁切）
        effectView.layer?.cornerRadius = r
        // 3. shadowWrapper 的 shadowPath（阴影跟着圆角变）
        if let wrapper = effectView.superview, let wlayer = wrapper.layer {
            wlayer.shadowPath = CGPath(
                roundedRect: wrapper.bounds,
                cornerWidth: r, cornerHeight: r,
                transform: nil
            )
        }
    }

    private func syncPanelAppearance() {
        let override = ColorSchemeOverride(rawValue: state.config.colorSchemeOverride) ?? .system
        let appearance: NSAppearance? = {
            switch override {
            case .system: return nil
            case .light:  return NSAppearance(named: .aqua)
            case .dark:   return NSAppearance(named: .darkAqua)
            }
        }()
        AppDelegate.shared?.panel?.appearance = appearance
        AppDelegate.shared?.quickCapturePanel?.appearance = appearance
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

// PanelWatermark 已移除：装饰水印跟输入框抢底部空间，跟"减一切冗余"哲学冲突
