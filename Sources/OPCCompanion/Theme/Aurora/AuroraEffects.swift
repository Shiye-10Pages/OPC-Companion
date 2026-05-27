import SwiftUI

// MARK: - J. ShimmerBorder ViewModifier
// 通用流光描边——TimelineView 驱动旋转角度，AngularGradient mask 成 stroke

struct ShimmerBorder: ViewModifier {
    let active: Bool
    let cornerRadius: CGFloat
    let colors: [Color]
    let lineWidth: CGFloat
    let speed: Double

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                TimelineView(.animation) { tl in
                    let angle = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: speed) / speed
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            AngularGradient(
                                colors: colors + [colors.first ?? .clear],
                                center: .center,
                                angle: .degrees(angle * 360)
                            ),
                            lineWidth: lineWidth
                        )
                }
            }
        }
    }
}

extension View {
    func shimmerBorder(
        active: Bool,
        cornerRadius: CGFloat,
        colors: [Color] = [
            Color(hex: "#E8A4C9"),
            Color(hex: "#B48CE6"),
            Color(hex: "#8CAAEB"),
            Color(hex: "#4ED8C0"),
            Color(hex: "#FFB78A"),
            Color(hex: "#E8A4C9")
        ],
        lineWidth: CGFloat = 1,
        speed: Double = 2.4
    ) -> some View {
        modifier(ShimmerBorder(active: active, cornerRadius: cornerRadius,
                               colors: colors, lineWidth: lineWidth, speed: speed))
    }
}

// MARK: - E. Aurora 用户气泡边缘流光（彩虹细描边）

struct AuroraEdgeGlow: ViewModifier {
    let active: Bool
    let cornerRadius: CGFloat
    @State private var hueShift: Double = 0

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                TimelineView(.animation(minimumInterval: 1.0/30)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    let shift = sin(t * .pi * 2 / 6.0) * 18  // 6s 周期，±18° 色相偏移
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color(hex: "#F8B8D8").opacity(0.70),
                                    Color(hex: "#B496E6").opacity(0.65),
                                    Color(hex: "#92B4EB").opacity(0.60),
                                    Color(hex: "#FFC8A8").opacity(0.55)
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                        .hueRotation(.degrees(shift))
                        .opacity(0.62)
                }
            }
        }
    }
}

extension View {
    func auroraEdgeGlow(active: Bool, cornerRadius: CGFloat) -> some View {
        modifier(AuroraEdgeGlow(active: active, cornerRadius: cornerRadius))
    }
}

// MARK: - F. 液态凝结入场过渡

extension AnyTransition {
    /// Aurora 新消息出现时的"液态凝结"——比简单 fadeIn 高级一档
    static var liquidIn: AnyTransition {
        .modifier(
            active: LiquidInModifier(progress: 0),
            identity: LiquidInModifier(progress: 1)
        )
    }
}

// Swift 6: Animatable 不能跨 MainActor —— 加 @preconcurrency
private struct LiquidInModifier: ViewModifier, @preconcurrency Animatable {
    var progress: Double  // 0 → 1
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    nonisolated func body(content: Content) -> some View {
        content
            .opacity(progress)
            .blur(radius: (1 - progress) * 8)
            .scaleEffect(0.94 + 0.06 * progress)
            .offset(y: (1 - progress) * 6)
    }
}

// MARK: - G. burstFlash 入场闪光

struct BurstFlash: View {
    let accent: Color
    @State private var opacity: Double = 0
    @State private var scale: Double = 0.5

    var body: some View {
        RadialGradient(
            colors: [accent.opacity(0.18), accent.opacity(0.10), .clear],
            center: .center, startRadius: 0, endRadius: 400
        )
        .scaleEffect(scale)
        .opacity(opacity)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .onAppear { trigger() }
    }

    func trigger() {
        opacity = 0
        scale = 0.5
        withAnimation(.easeOut(duration: 0.3)) {
            opacity = 0.7
            scale = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.7)) {
                opacity = 0
                scale = 1.5
            }
        }
    }
}

// MARK: - H. Aurora 输入框 focus 三圈光晕

struct AuroraFocusRings: ViewModifier {
    let active: Bool
    let cornerRadius: CGFloat
    let accent: Color

    func body(content: Content) -> some View {
        content
            .shadow(color: active ? accent.opacity(0.40) : .clear, radius: 8,  x: 0, y: 4)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(active ? accent.opacity(0.45) : .clear, lineWidth: 5)
                    .blur(radius: 4)
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(active ? accent.opacity(0.14) : .clear, lineWidth: 10)
                    .blur(radius: 10)
            )
    }
}

extension View {
    func auroraFocusRings(active: Bool, cornerRadius: CGFloat, accent: Color) -> some View {
        modifier(AuroraFocusRings(active: active, cornerRadius: cornerRadius, accent: accent))
    }
}

// MARK: - I. AuroraTypingIndicator —— shimmer 气泡占位符

/// 替代 3 圆点：一个气泡形状的 placeholder + 横扫流光
/// 仅在 Aurora 主题下使用
struct AuroraShimmerTyping: View {
    @Environment(\.theme) private var theme

    var body: some View {
        // 气泡形状（与 AI 气泡一致的不对称圆角）
        UnevenRoundedRectangle(cornerRadii: .init(
            topLeading: theme.bubbleCornerRadius,
            bottomLeading: 8,
            bottomTrailing: theme.bubbleCornerRadius,
            topTrailing: theme.bubbleCornerRadius
        ))
        .fill(.ultraThinMaterial)
        .overlay(
            UnevenRoundedRectangle(cornerRadii: .init(
                topLeading: theme.bubbleCornerRadius,
                bottomLeading: 8,
                bottomTrailing: theme.bubbleCornerRadius,
                topTrailing: theme.bubbleCornerRadius
            ))
            .stroke(theme.textTertiary.opacity(0.20), lineWidth: 0.5)
        )
        .overlay {
            // 横扫的高光
            TimelineView(.animation(minimumInterval: 1.0/30)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                let progress = (t.truncatingRemainder(dividingBy: 1.8)) / 1.8   // 0 → 1，1.8s 周期
                let x = (progress * 2 - 0.5)                                    // -0.5 → 1.5
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.25), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.4)
                    .offset(x: geo.size.width * (x - 0.2))
                    .blendMode(.plusLighter)
                }
            }
        }
        .clipShape(UnevenRoundedRectangle(cornerRadii: .init(
            topLeading: theme.bubbleCornerRadius,
            bottomLeading: 8,
            bottomTrailing: theme.bubbleCornerRadius,
            topTrailing: theme.bubbleCornerRadius
        )))
        .frame(width: 90, height: 36)
        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
    }
}
