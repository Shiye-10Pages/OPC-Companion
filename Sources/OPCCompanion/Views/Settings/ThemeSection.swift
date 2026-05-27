import SwiftUI

/// 设置页中的「外观主题」选择区块
struct ThemeSection: View {
    @EnvironmentObject var state: AppState
    @StateObject private var themeProvider = ThemeProvider.shared
    @State private var showPromptInspector = false

    private var currentID: ThemeID {
        ThemeID(rawValue: state.config.themeID) ?? .aurora
    }

    private var currentScheme: ColorSchemeOverride {
        ColorSchemeOverride(rawValue: state.config.colorSchemeOverride) ?? .system
    }

    private var currentFontStyle: FontStyleID {
        FontStyleID(rawValue: state.config.fontStyleID) ?? .readable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("外观主题")
                    .font(.headline)
                Text("主题不是换皮，是换 AI 的灵魂")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // 2 × 2 网格
            let columns = [GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ThemeID.allCases, id: \.self) { id in
                    ThemeCard(
                        id: id,
                        isSelected: id == currentID,
                        isAvailable: ThemeCard.isFullyImplemented(id),
                        onTap: { select(id) }
                    )
                }
            }

            // 颜色方案
            Divider().padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 8) {
                Text("颜色方案")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Picker("", selection: Binding(
                    get: { currentScheme },
                    set: { selectScheme($0) }
                )) {
                    ForEach(ColorSchemeOverride.allCases, id: \.self) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // 字体方案
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("字体方案")
                        .font(.subheadline)
                    Text("「可读优先」默认；其它三套按调性选")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)],
                          spacing: 8) {
                    ForEach(FontStyleID.allCases, id: \.self) { id in
                        FontStyleCard(
                            id: id,
                            isSelected: id == currentFontStyle,
                            isRecommendedForCurrent: id.recommendedFor.contains(currentID),
                            onTap: { selectFontStyle(id) }
                        )
                    }
                }
            }

            // 主题给 AI 的提示词（只读，可折叠）
            Divider().padding(.vertical, 4)
            ThemePromptInspector(
                themeID: currentID,
                prompt: themeProvider.current.systemPromptAppendix,
                isOpen: $showPromptInspector
            )
        }
    }

    private func select(_ id: ThemeID) {
        guard ThemeCard.isFullyImplemented(id) else { return }
        var cfg = state.config
        cfg.themeID = id.rawValue
        state.config = cfg
        state.saveConfig()
    }

    private func selectScheme(_ s: ColorSchemeOverride) {
        var cfg = state.config
        cfg.colorSchemeOverride = s.rawValue
        state.config = cfg
        state.saveConfig()
    }

    private func selectFontStyle(_ id: FontStyleID) {
        var cfg = state.config
        cfg.fontStyleID = id.rawValue
        state.config = cfg
        state.saveConfig()
    }
}

// MARK: - ThemePromptInspector

/// 显示当前主题注入到 AI 的 system prompt 附录（只读）。
/// 让用户能看到「主题给 AI 的灵魂指令」到底是什么，理解为什么 Aurora 像 Aurora、Stoa 像 Stoa。
struct ThemePromptInspector: View {
    let themeID: ThemeID
    let prompt: String
    @Binding var isOpen: Bool
    @State private var copied = false

    private var isEmpty: Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { isOpen.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text("查看「\(themeID.displayName)」给 AI 的提示词")
                            .font(.subheadline)
                        if isEmpty {
                            Text("（该主题无附加 prompt）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                if isOpen && !isEmpty {
                    Button {
                        copyToPasteboard()
                    } label: {
                        Label(copied ? "已复制" : "复制",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(copied ? Color.green : .secondary)
                }
            }

            if isOpen && !isEmpty {
                ScrollView {
                    Text(prompt)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 260)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("此 prompt 会拼在你的 base 系统提示词之后，每次发消息都会送给 AI。改主题即可换 prompt；不能在此处直接编辑。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func copyToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(prompt, forType: .string)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { copied = false }
        }
    }
}

// MARK: - FontStyleCard

struct FontStyleCard: View {
    let id: FontStyleID
    let isSelected: Bool
    let isRecommendedForCurrent: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                // 字样预览：用该字体方案的 bodyFont 渲染示例汉字
                let preview = FontStyleSet.from(id)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aa 你好")
                        .font(preview.bodyFont)
                        .foregroundStyle(.primary)
                    Text("写稿 · 进展")
                        .font(preview.titleFont)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 80, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(id.displayName)
                            .font(.system(size: 12, weight: .semibold))
                        if isRecommendedForCurrent && id != .readable {
                            Text("· 推荐")
                                .font(.system(size: 9))
                                .foregroundStyle(.tint)
                        }
                    }
                    Text(id.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.08),
                            lineWidth: isSelected ? 1.5 : 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .scaleEffect(isHovered ? 1.01 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.18), value: isHovered)
        .animation(.easeOut(duration: 0.22), value: isSelected)
    }
}

// MARK: - Card

struct ThemeCard: View {
    let id: ThemeID
    let isSelected: Bool
    let isAvailable: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    /// 本次仅 Aurora / Stoa 完整实现，Wabi / Flow 占位
    static func isFullyImplemented(_ id: ThemeID) -> Bool {
        switch id {
        case .aurora, .stoa: return true
        case .wabi, .flow:   return false
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // 顶部色彩 swatch（每个主题独有的"招牌画面"）
                ZStack(alignment: .topTrailing) {
                    swatchView
                        .frame(height: 72)
                        .clipped()

                    if !isAvailable {
                        Text("敬请期待")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.thinMaterial, in: Capsule())
                            .padding(6)
                    }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white, .black.opacity(0.55))
                            .padding(6)
                    }
                }

                // 信息区
                VStack(alignment: .leading, spacing: 3) {
                    Text(id.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(id.tagline)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.08),
                            lineWidth: isSelected ? 1.5 : 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(isAvailable ? 1 : 0.55)
            .scaleEffect(isHovered && isAvailable ? 1.015 : 1)
            .shadow(color: isSelected ? Color.accentColor.opacity(0.20) : .clear,
                    radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.18), value: isHovered)
        .animation(.easeOut(duration: 0.25), value: isSelected)
    }

    /// 每个主题的"招牌画面"—— mini 预览
    @ViewBuilder
    private var swatchView: some View {
        switch id {
        case .aurora:
            // 紫粉蓝 mesh 光团缩影
            ZStack {
                LinearGradient(colors: [Color(hex: "#1a0d2e"), Color(hex: "#0d0a26")],
                               startPoint: .top, endPoint: .bottom)
                Circle().fill(RadialGradient(colors: [Color(hex: "#E8A4C9"), .clear],
                                             center: .center, startRadius: 0, endRadius: 50))
                    .frame(width: 90, height: 90)
                    .offset(x: -40, y: -10)
                    .blur(radius: 12)
                Circle().fill(RadialGradient(colors: [Color(hex: "#7AB8E8"), .clear],
                                             center: .center, startRadius: 0, endRadius: 50))
                    .frame(width: 90, height: 90)
                    .offset(x: 40, y: 15)
                    .blur(radius: 12)
                Circle().fill(RadialGradient(colors: [Color(hex: "#FFB78A"), .clear],
                                             center: .center, startRadius: 0, endRadius: 40))
                    .frame(width: 70, height: 70)
                    .offset(x: 0, y: 20)
                    .blur(radius: 12)
            }
        case .stoa:
            // 素白纸 + 一根朱砂笔印 + 拉丁词
            ZStack(alignment: .trailing) {
                LinearGradient(colors: [Color(hex: "#0a0c10"), Color(hex: "#060810")],
                               startPoint: .top, endPoint: .bottom)
                // 极淡分界线（横贯）
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.5)
                // 朱砂笔印
                Rectangle()
                    .fill(Color(hex: "#c85549"))
                    .frame(width: 1.5, height: 14)
                    .rotationEffect(.degrees(8))
                    .padding(.trailing, 10)
                    .padding(.top, 36)
                // 拉丁词
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Quid hodie?")
                        .font(.custom("New York", size: 9).italic())
                        .foregroundStyle(Color(hex: "#c85549").opacity(0.70))
                    Text("今天，由谁？")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.30))
                }
                .padding(.trailing, 10)
                .padding(.top, 8)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        case .wabi:
            // 墨色 + 朱砂落款
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(colors: [Color(hex: "#1a1612"), Color(hex: "#0d0c0a")],
                               startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(Color.black.opacity(0.40))
                    .frame(width: 60, height: 60)
                    .blur(radius: 14)
                    .offset(x: -30, y: -10)
                // 朱砂印章
                Text("伴")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color(hex: "#f5ecd0"))
                    .frame(width: 16, height: 16)
                    .background(Color(hex: "#c8413f"))
                    .rotationEffect(.degrees(-2))
                    .padding(8)
            }
        case .flow:
            // 暖琥珀单色 + 中央光柱
            ZStack {
                LinearGradient(colors: [Color(hex: "#1a0e04"), Color(hex: "#050403")],
                               startPoint: .top, endPoint: .bottom)
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, Color(hex: "#FFB870").opacity(0.5), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 2)
                    .blur(radius: 3)
            }
        }
    }
}
