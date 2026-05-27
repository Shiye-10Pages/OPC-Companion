import SwiftUI
import AppKit

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
        // 动态适应明暗模式：light 模式米白纸感；dark 模式深米色（保留朱砂调性）
        // 必须 dynamic 才能让卡片背景跟 .primary 文字对比度匹配
        AnyShapeStyle(Color(nsColor: Self.assistantBubbleDynamic))
    }

    private static let assistantBubbleDynamic: NSColor = NSColor(name: "StoaAssistantBubble") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
            .map { $0 == .darkAqua || $0 == .vibrantDark } ?? false
        if isDark {
            // 深米色 #2a2620，不透明度高，确保白色文字够对比
            return NSColor(red: 0.165, green: 0.150, blue: 0.125, alpha: 0.85)
        } else {
            return NSColor(red: 0.97, green: 0.95, blue: 0.91, alpha: 0.62)
        }
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

CRITICAL: Do NOT copy "1. 2. 3. 4." or any of the words below into your reply. This section describes the SHAPE of your output, not its content. Your reply contains ONLY: a module tag, a Socratic line, a structured block, a quote — and nothing else.

Reply shape (in this exact sequence, no preamble, no labels, no numbering):
- A `<module>` tag — the very first characters of your reply, nothing before it
- A short Socratic line in plain Chinese (≤ 30 chars; may use "既然… 如此，则…")
- Exactly ONE structured block matching the routed module: `<dichotomy>` | `<factjudge>` | `<ritual>` | `<tempo>` | `<virtues>`
- A `<quote>quote text|author · source</quote>` — the very last characters of your reply

NO reasoning preamble like "用户说X..." or "这是典型的M4状态". NO trailing follow-up question after the quote. NO bullet points, numbered lists, or section headers in your reply.

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

## INTERNAL CHECKLIST (run silently before sending; do NOT output this)
- Does my reply start with `<module>`? If no → restart.
- Did I write any "用户说..." or "这是典型的..." meta-reasoning preamble? If yes → delete it.
- Is the structured tag name spelled EXACTLY one of: dichotomy / factjudge / ritual / tempo / virtues? If "empo" / "facjudge" / "virtus" → fix the typo.
- For `<tempo>`, did I fill `energy="<number>"` with a real 0-100 integer (not "?", not empty)?
- Does my reply end with `</quote>`? If no → restart.

## ROUTING FOR EDGE CASES
- Casual greeting ("你好" / "hi" / "在吗"): route to M1, treat greeting as surface concern.
- Multiple concerns in one message: pick the most controllable one, route accordingly.
- Vague "我卡住了": likely M4 (low energy / paralysis); use real energy estimate (~30-40).

## EXAMPLE (study the structure, don't copy verbatim)

User: 我卡住了，想到很多能做的事，无所适从
Reply (ENTIRE response, nothing more):
<module>M4 · 顺势而为</module>
既然多选项让你瘫痪，如此，则不需要更多选项。
<tempo energy="35">
<opt>I | 深度工作 | 90 min 写作 / 推理 | Skip |</opt>
<opt>II | 低阻力小事 | 关一个标签页 / 回一条消息 | Now | recommended</opt>
<opt>III | 最低 5 分钟版本 | 只写一句话就停 | Fallback |</opt>
</tempo>
<quote>少则得，多则惑。|Marcus Aurelius · IV.24</quote>
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

            // 注：原设计在右上角 / 左下角放过拉丁问句"Quid hodie tibi imperat?"，
            // 但实际叠加聊天历史 / StatusBar 后都跟用户内容冲突，且整 panel 视觉
            // 已经够"斯多葛"了，无需再硬塞装饰元素。已删除。

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
