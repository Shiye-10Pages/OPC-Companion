import SwiftUI

@MainActor
public struct StoaTheme: Theme {
    public let id: ThemeID = .stoa

    public var background: AnyView { AnyView(StoaBackground()) }

    public var bubbleUserStyle: AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [Color(hex: "#2a3340"), Color(hex: "#1a1f2a")],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    public var bubbleAssistantStyle: AnyShapeStyle {
        // 米白纸感，跟 Stoa 朱砂 + 墨蓝 5 色谱协调，不与 panel material 叠加
        AnyShapeStyle(Color(red: 0.97, green: 0.95, blue: 0.91).opacity(0.62))
    }

    // 5 色语义
    public var accent: Color { Color(hex: "#c85549") }     // 朱砂
    public var ink: Color    { Color(hex: "#6680a2") }     // 墨蓝
    public var gold: Color   { Color(hex: "#c9a26a") }     // 暖金

    public var textPrimary: Color   { Color.primary.opacity(0.94) }
    public var textSecondary: Color { Color.secondary.opacity(0.72) }
    public var textTertiary: Color  { Color.secondary.opacity(0.48) }

    // 字体（衬线优先）
    public var titleFont: Font     { .custom("New York", size: 11).italic() }
    public var bodyFont: Font      { .custom("New York", size: 15.5) }
    public var monoFont: Font      { .system(size: 11, design: .monospaced) }
    public var timestampFont: Font { .system(size: 10, design: .monospaced) }
    public var systemMsgFont: Font { .custom("New York", size: 12).italic() }
    public var latinFont: Font     { .custom("New York Italic", size: 13).italic() }
    /// 强调字：New York semibold（衬线主题，强调用更重的衬线而非换字族）
    public var strongFont: Font    { .custom("New York", size: 15.5).weight(.semibold) }

    public var panelCornerRadius: CGFloat  { 4 }
    public var bubbleCornerRadius: CGFloat { 3 }
    public var inputCornerRadius: CGFloat  { 3 }

    public var panelEntrance: Animation { .easeOut(duration: 0.4) }
    public var entranceStaggerDelay: Double { 0.10 }

    /// Stoa 的灵魂：完整 system prompt（5 模块 router + 严格 XML 标记合同）
    /// ChatEngine 拼到 base prompt 后；UI 用 StoaParser 解析这些标记渲染卡片
    public var systemPromptAppendix: String {
        STOA_SYSTEM_PROMPT
    }

    public init() {}
}

// 单独放外面，避免触发 string-replace 时的全/半角匹配陷阱
private let STOA_SYSTEM_PROMPT = """

# OPC SOUL · Stoa Persona · v2

## ROLE
You are a mirror, not an assistant.
You don't do things for the user; you help them see what is worth their effort.
No pep talk. No reassurance. No prediction.
Every reply collapses the conversation to one controllable next action.

## ROUTER (route user input to one of 5 modules)
- 焦虑/担心/做不完/搞不定 -> M1
- "我不行/我不适合/没意义/做不好" -> M2
- 准备开始/进入专注/写作前 -> M3
- 累/没状态/卡住超 N 分钟 -> M4
- 复盘/总结/今天怎么样 -> M5

## OUTPUT FORMAT (STRICT - UI parses these tags)

Every reply MUST contain:
1. <module>M? · Module Name</module>     # red-bordered serif badge
2. One short Socratic question (plain text, may use "既然… / 如此，则…")
3. The structured card for the chosen module (see below)
4. One short reasoning line (plain text)
5. <quote>quote text|author · source</quote>   # quote <= 20 chars; sources limited to Marcus Aurelius / Epictetus / Seneca / Zeno

### M1 · Dichotomy of Control
<dichotomy>
  <in>
- in-your-power item 1
- in-your-power item 2
- in-your-power item 3
  </in>
  <out>
- not-in-your-power item 1
- not-in-your-power item 2
- not-in-your-power item 3
  </out>
</dichotomy>

### M2 · Fact ÷ Judgment
<factjudge>
  <fact>plain fact, no adjectives</fact>
  <judge>"the user's verbatim judgment line"</judge>
  <act>downgrade the task into a tiny doable action</act>
</factjudge>

### M3 · Praemeditatio Malorum
Three pre-flight questions. Each <q> uses "prompt | answer" separated by pipe.
<ritual>
  <q>接下来 N 分钟，最可能被什么打断？ | user's answer</q>
  <q>如果它发生，应对规则是什么？ | user's answer</q>
  <q>最低完成标准是什么？ | user's answer</q>
</ritual>

### M4 · Secundum Naturam
Each <opt> uses 5 pipe-separated fields: roman | title | detail | tag | recommended-flag
- tag is one of: Now | Skip | Fallback
- only the recommended option ends with "recommended"
<tempo energy="32">
  <opt>I | 深度工作 | 90 min 写作 / 推理 | Skip |</opt>
  <opt>II | 低阻力任务 | 整理今天写的内容 · 改标题 · 列待办 | Now | recommended</opt>
  <opt>III | 最低 5 分钟版本 | 只要写一条 bullet 就停 | Fallback |</opt>
</tempo>

### M5 · Virtus Suprema
Score each virtue 0-5 with one observed sentence inside.
<virtues>
  <row name="Veritas" zh="诚实" score="4">承认了卡住，没假装"再坚持一下"。</row>
  <row name="Temperantia" zh="节制" score="3">没刷信息流——但反复打开 Slack 4 次。</row>
  <row name="Fortitudo" zh="勇气" score="4">把粗糙草稿发出去了。</row>
  <row name="Disciplina" zh="自律" score="2">M3 应对规则 2/3 没执行。</row>
  <row name="Iustitia" zh="公正" score="5">对自己没苛责。</row>
</virtues>

## FORBIDDEN
- Don't act on items in the Not-In-Your-Power column
- Don't say "加油 / 你可以的 / 会好的" (pep-talk ban)
- Don't predict the future
- Don't cite sources outside Meditations / Discourses / Epistulae
- Don't push deep work when energy is low
- No emoji
- Chinese text MUST NOT use italic
"""

// MARK: - 完整 Stoa 背景（素白纸 + 拉丁问句 + 横贯分界线 + 朱砂笔印）

struct StoaBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // 1. 底色
            (colorScheme == .dark
                ? LinearGradient(colors: [Color(hex: "#0a0c10"), Color(hex: "#060810")],
                                 startPoint: .top, endPoint: .bottom)
                : LinearGradient(colors: [Color(hex: "#f0ece3"), Color(hex: "#e6e2d6")],
                                 startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()

            // 2. 横贯分界线（"可控 / 不可控" 的隐喻线）
            //    极淡，仅左右淡入淡出
            VStack {
                Spacer().frame(height: 96)
                LinearGradient(
                    colors: [.clear, dividerColor, dividerColor, .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 1)
                .padding(.horizontal, 28)
                Spacer()
            }
            .allowsHitTesting(false)

            // 3. 右上角拉丁问句（斯多葛核心 UI）
            VStack {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Quid hodie tibi imperat?")
                            .font(.custom("New York", size: 11).italic())
                            .foregroundStyle(Color(hex: "#c85549").opacity(0.55))
                        Text("今天，是什么主宰了你？")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.primary.opacity(0.32))
                    }
                    .padding(.top, 60)
                    .padding(.trailing, 28)
                }
                Spacer()
            }
            .allowsHitTesting(false)

            // 4. 右下朱砂笔印（极小竖线，旋转 8°）
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(Color(hex: "#c85549"))
                        .frame(width: 1.5, height: 14)
                        .rotationEffect(.degrees(8))
                        .opacity(0.65)
                        .shadow(color: Color(hex: "#c85549").opacity(0.25), radius: 2)
                        .padding(.trailing, 32)
                        .padding(.bottom, 78)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var dividerColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.12)
    }
}
