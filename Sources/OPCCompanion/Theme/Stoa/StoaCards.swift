import SwiftUI

// MARK: - ModuleTag

/// 朱砂边框、衬线 italic 模块标签，对应 demo 中的 .module-tag
struct StoaModuleTag: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(theme.accent)
                .frame(width: 4, height: 4)
                .shadow(color: theme.accent.opacity(0.85), radius: 3)
            Text(text)
                .font(.custom("New York", size: 11.5).italic())
                .tracking(0.4)
                .foregroundStyle(theme.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(theme.accent, lineWidth: 0.5)
        )
    }
}

// MARK: - DichotomyCard

/// 两栏拆分：可控 / 不可控
struct StoaDichotomyCard: View {
    @Environment(\.theme) private var theme
    let inn: [String]
    let out: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            column(label: "In Your Power",     color: theme.ink, items: inn)
            column(label: "Not In Your Power", color: theme.accent, items: out)
        }
        .padding(.vertical, 6)
    }

    private func column(label: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("·")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(color.opacity(0.65))
                        Text(line)
                            .font(theme.bodyFont)
                            .foregroundStyle(.primary.opacity(0.92))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle().fill(color).frame(width: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - FactJudgeCard

/// 事实 ÷ 判断 ÷ 行动 三行
struct StoaFactJudgeCard: View {
    @Environment(\.theme) private var theme
    let fact: String
    let judge: String
    let action: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(key: "Fact",     value: fact,   color: theme.ink, style: .normal)
            divider
            row(key: "Judgment", value: judge,  color: theme.accent, style: .struck)
            divider
            row(key: "Action",   value: action, color: theme.ink, style: .strong)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
        .overlay(alignment: .leading) {
            Rectangle().fill(theme.accent).frame(width: 2)
        }
        .background(
            RoundedRectangle(cornerRadius: 3)
                .stroke(theme.textTertiary.opacity(0.30), lineWidth: 0.5)
        )
    }

    enum Style { case normal, struck, strong }

    private var divider: some View {
        Rectangle()
            .fill(theme.textTertiary.opacity(0.25))
            .frame(height: 0.5)
            .padding(.vertical, 1)
    }

    private func row(key: String, value: String, color: Color, style: Style) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(key)
                .font(.system(size: 9.5, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(color)
                .frame(width: 60, alignment: .leading)
                .padding(.top, 3)
            Text(value)
                .font(theme.bodyFont)
                .foregroundStyle(style == .struck ? theme.textTertiary : theme.textPrimary)
                .strikethrough(style == .struck, color: theme.accent.opacity(0.65))
                .fontWeight(style == .strong ? .medium : .regular)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 7)
    }
}

// MARK: - RitualCard

/// 启动仪式三问
struct StoaRitualCard: View {
    @Environment(\.theme) private var theme
    let items: [(prompt: String, answer: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                if idx > 0 {
                    Rectangle()
                        .fill(theme.textTertiary.opacity(0.25))
                        .frame(height: 0.5)
                }
                HStack(alignment: .top, spacing: 12) {
                    Text(roman(idx + 1) + ".")
                        .font(.custom("New York", size: 13).italic())
                        .foregroundStyle(theme.gold)
                        .frame(width: 22, alignment: .leading)
                        .padding(.top, 11)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.prompt)
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.ink)
                            .fontWeight(.medium)
                        if !item.answer.isEmpty {
                            Text(item.answer)
                                .font(theme.bodyFont)
                                .foregroundStyle(theme.textPrimary)
                                .padding(.leading, 10)
                                .padding(.vertical, 4)
                                .padding(.trailing, 10)
                                .background(
                                    theme.ink.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 2)
                                )
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(theme.ink).frame(width: 2)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 9)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(theme.textTertiary.opacity(0.30), lineWidth: 0.5)
        )
        .overlay(alignment: .topLeading) {
            Text("Praemeditatio")
                .font(.custom("New York", size: 11).italic())
                .tracking(0.7)
                .foregroundStyle(theme.gold)
                .padding(.horizontal, 6)
                .background(Color.clear)
                .offset(x: 12, y: -7)
        }
    }
}

// MARK: - TempoCard

struct StoaTempoCard: View {
    @Environment(\.theme) private var theme
    /// energyPct 仍接收（兼容历史 <tempo energy="X"> 标签）但不再渲染 —— 那是 AI 主观估算，
    /// 不接入任何真实信号源，曾以"系统判断"的姿态出现具有误导性，已删除。
    /// 仅保留 3 个 tempo 选项 + recommended 标记作为轻量信号。
    let energyPct: Int
    let options: [TempoOption]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                optionRow(opt)
            }
        }
    }

    private func optionRow(_ opt: TempoOption) -> some View {
        HStack(spacing: 12) {
            Text(opt.roman + ".")
                .font(.custom("New York", size: 13).italic())
                .foregroundStyle(theme.gold)
                .frame(width: 24, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(opt.title)
                    .font(theme.bodyFont)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary.opacity(0.94))
                Text(opt.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary.opacity(0.55))
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // tag 标签：Skip / Now / Fallback
            Text(opt.tag.uppercased())
                .font(.system(size: 8.5, design: .monospaced))
                .tracking(2.0)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(tagColor(opt), lineWidth: 0.5))
                .foregroundStyle(tagColor(opt))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(opt.recommended ? theme.ink.opacity(0.10) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(opt.recommended ? theme.ink : theme.textTertiary.opacity(0.30),
                        lineWidth: 0.5)
        )
    }

    private func tagColor(_ opt: TempoOption) -> Color {
        switch opt.tag.lowercased() {
        case "now":      return theme.accent
        case "skip":     return theme.accent.opacity(0.40)
        case "fallback": return theme.ink
        default:         return theme.textTertiary
        }
    }
}

// MARK: - VirtuesCard

struct StoaVirtuesCard: View {
    @Environment(\.theme) private var theme
    let rows: [VirtueRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                if idx > 0 {
                    Rectangle().fill(theme.textTertiary.opacity(0.25)).frame(height: 0.5)
                }
                HStack(spacing: 14) {
                    // 拉丁名 + 中文
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name)
                            .font(.custom("New York", size: 13).italic())
                            .tracking(0.3)
                            .foregroundStyle(theme.gold)
                        Text(row.chineseName)
                            .font(.system(size: 8.5, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(theme.textTertiary)
                    }
                    .frame(width: 100, alignment: .leading)

                    // 5 颗墨点
                    HStack(spacing: 5) {
                        ForEach(0..<5, id: \.self) { i in
                            Circle()
                                .fill(i < row.score
                                      ? AnyShapeStyle(RadialGradient(
                                          colors: [theme.ink.opacity(0.95), theme.ink.opacity(0.55), theme.ink.opacity(0.20)],
                                          center: .init(x: 0.32, y: 0.30),
                                          startRadius: 1, endRadius: 7))
                                      : AnyShapeStyle(theme.textTertiary.opacity(0.30)))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .frame(width: 80, alignment: .leading)

                    // 一句观察
                    Text(row.note)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 9)
            }
        }
    }
}

// MARK: - QuoteTail

/// 引言尾签：大引号 + 衬线 italic + monospace 出处
struct StoaQuoteTail: View {
    @Environment(\.theme) private var theme
    let text: String
    let author: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\u{201C}")
                .font(.custom("New York", size: 28))
                .foregroundStyle(theme.accent.opacity(0.75))
                .padding(.trailing, 4)
                .offset(y: 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.custom("New York", size: 12).italic())
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !author.isEmpty {
                    Text("— " + author.uppercased())
                        .font(.system(size: 9.5, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.textTertiary.opacity(0.30))
                .frame(height: 0.5)
                .padding(.horizontal, 0)
        }
    }
}

// MARK: - 小工具

private func roman(_ n: Int) -> String {
    let table: [(Int, String)] = [(10,"X"),(9,"IX"),(5,"V"),(4,"IV"),(1,"I")]
    var n = n
    var out = ""
    for (v, s) in table {
        while n >= v { out += s; n -= v }
    }
    return out
}
