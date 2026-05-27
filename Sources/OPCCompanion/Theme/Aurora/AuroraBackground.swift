import SwiftUI

/// Aurora 背景：5 个独立漂移的彩色光团 + 极细网格质地
/// 视觉锤本体——切到 Aurora 主题时，这就是"小红书惊艳"的核心
/// 性能：面板隐藏时 TimelineView 自动暂停，避免后台 60fps 渲染
struct AuroraBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            // 底色
            (colorScheme == .dark
                ? LinearGradient(colors: [Color(hex: "#1a0d2e"), Color(hex: "#0d0a26")],
                                 startPoint: .top, endPoint: .bottom)
                : LinearGradient(colors: [Color(hex: "#faf0f5"), Color(hex: "#e8e0f0")],
                                 startPoint: .top, endPoint: .bottom))
            .ignoresSafeArea()

            // 5 个独立漂移的光团；面板隐藏时 paused=true
            TimelineView(.animation(minimumInterval: 1.0/30, paused: !state.isPanelVisible)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                ZStack {
                    blob(color: Color(hex: "#E8A4C9"), size: 480,
                         x: -100 + drift(t, period: 22, amp: 180),
                         y: -120 + drift(t, period: 18, amp: 100),
                         scale: 1.0 + drift(t, period: 20, amp: 0.12))
                    blob(color: Color(hex: "#7AB8E8"), size: 520,
                         x: 380 + drift(t, period: 28, amp: -160),
                         y: -80 + drift(t, period: 24, amp: 140),
                         scale: 1.0 + drift(t, period: 26, amp: 0.16))
                    blob(color: Color(hex: "#5A3FAA"), size: 600,
                         x: 152 + drift(t, period: 26, amp: -100),
                         y: 360 + drift(t, period: 22, amp: -120),
                         scale: 1.0 + drift(t, period: 30, amp: 0.10))
                    blob(color: Color(hex: "#FFB78A"), size: 380,
                         x: 380 + drift(t, period: 32, amp: -180),
                         y: 480 + drift(t, period: 28, amp: -100),
                         scale: 1.0 + drift(t, period: 34, amp: 0.18))
                    blob(color: Color(hex: "#4ED8C0"), size: 320,
                         x: 266 + drift(t, period: 36, amp: -120),
                         y: 182 + drift(t, period: 30, amp: 80),
                         scale: 0.9 + drift(t, period: 36, amp: 0.30),
                         opacity: 0.5)
                }
                .blur(radius: 60)
                .blendMode(colorScheme == .dark ? .screen : .multiply)
            }
            .opacity(colorScheme == .dark ? 0.85 : 0.55)

            // 极细网格质地（远看哑光磨砂质感）
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                Path { p in
                    for x in stride(from: 0, through: w, by: 36) { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h)) }
                    for y in stride(from: 0, through: h, by: 36) { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y)) }
                }
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.015 : 0.025), lineWidth: 0.5)
                .blendMode(.overlay)
            }
            .allowsHitTesting(false)

            // 顶部环境反射高光（色相对比，不是亮度——避免暗色刺眼）
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        .clear,
                        Color(hex: "#E8A4C9").opacity(0.30),
                        Color(hex: "#B48CE6").opacity(0.40),
                        Color(hex: "#8CAAEB").opacity(0.35),
                        .clear
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 1)
                .blur(radius: 0.5)
                .opacity(colorScheme == .dark ? 0.55 : 0.85)
                .padding(.horizontal, 60)
                Spacer()
            }
        }
    }

    /// 缓慢漂移函数（用 sin 复合不同周期，制造非线性轨迹）
    private func drift(_ t: TimeInterval, period: Double, amp: Double) -> Double {
        sin(t * .pi * 2 / period) * amp
    }

    @ViewBuilder
    private func blob(color: Color, size: CGFloat, x: Double, y: Double, scale: Double, opacity: Double = 0.85) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color, color.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .scaleEffect(scale)
            .offset(x: x, y: y)
            .opacity(opacity)
    }
}

// Note: Color(hex:) 已在 Utils/AppDesignSystem.swift 中定义，本文件复用之
