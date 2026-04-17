import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedDay: String?
    @State private var selectedContent: String = ""
    @State private var activityCache: [String: Int] = [:]
    @State private var weeklyReport: String?
    @State private var showWeeklyReport = false

    var body: some View {
        HStack(spacing: 0) {
            calendarPanel
                .frame(width: 155)

            Divider().opacity(0.5)

            detailPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 左栏：日历

    private let dayColumns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private static let weekdayHeaders = ["一", "二", "三", "四", "五", "六", "日"]

    private var calendarPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 星期列头
            LazyVGrid(columns: dayColumns, spacing: 2) {
                ForEach(Self.weekdayHeaders, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(height: 12)
                }
            }

            // 日历格子 + 月份标注
            ScrollView {
                LazyVGrid(columns: dayColumns, spacing: 2) {
                    ForEach(Array(recentDays.enumerated()), id: \.element) { idx, key in
                        ZStack(alignment: .topLeading) {
                            dayCell(key)

                            // 每月 1 号标注月份
                            if key.hasSuffix("-01") || idx == 0 {
                                Text(monthLabel(key))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .offset(x: 1, y: 1)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
                .onAppear { preloadActivityCounts() }
            }
            .scrollIndicators(.automatic)

            // 图例
            HStack(spacing: 4) {
                legendDot(opacity: 0.08); Text("无").font(.system(size: 11))
                legendDot(opacity: 0.35); Text("少").font(.system(size: 11))
                legendDot(opacity: 0.7); Text("中").font(.system(size: 11))
                legendDot(opacity: 1.0); Text("多").font(.system(size: 11))
            }
            .foregroundStyle(.secondary)

            // 周报入口
            if let weeklyKey = currentWeeklyKey() {
                Button {
                    loadWeeklyReport(weeklyKey)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 11))
                        Text("本周周报")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    // MARK: - 右栏：详情

    @ViewBuilder
    private var detailPanel: some View {
        if showWeeklyReport, let report = weeklyReport {
            ScrollView {
                MarkdownText(text: report)
                    .font(.system(size: 11))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .overlay(alignment: .topTrailing) {
                Button {
                    showWeeklyReport = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        } else if selectedDay != nil {
            ScrollView {
                if selectedContent.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "doc")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                        Text("当日暂无记录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 60)
                } else {
                    MarkdownText(text: selectedContent)
                        .font(.system(size: 11))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollIndicators(.automatic)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                Text("选一天查看")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 格子

    private func dayCell(_ key: String) -> some View {
        let count = activityCache[key] ?? 0
        let opacity: Double = switch count {
        case 0: 0.06
        case 1...2: 0.3
        case 3...5: 0.65
        default: 1.0
        }
        let isSelected = selectedDay == key
        let isToday = key == todayKey

        return Button {
            showWeeklyReport = false
            selectedDay = key
            selectedContent = loadDailyNote(for: key)
        } label: {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(opacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(
                            isSelected ? Color.accentColor : (isToday ? Color.secondary.opacity(0.6) : Color.clear),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
                .frame(height: 16)
        }
        .buttonStyle(.plain)
        .help(key)
    }

    private func legendDot(opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.accentColor.opacity(opacity))
            .frame(width: 8, height: 8)
    }

    // MARK: - Data

    private var recentDays: [String] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return (0..<42).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today).map { f.string(from: $0) }
        }
    }

    private var todayKey: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func monthLabel(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count >= 2, let m = Int(parts[1]) else { return "" }
        return "\(m)月"
    }

    private func preloadActivityCounts() {
        let memoryDir = AppState.dataDirectory.appendingPathComponent("memory")
        Task.detached(priority: .utility) {
            var counts: [String: Int] = [:]
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            for offset in 0..<42 {
                guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
                let key = f.string(from: d)
                let url = memoryDir.appendingPathComponent("\(key).md")
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    counts[key] = content.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }.count
                }
            }
            await MainActor.run { [counts] in
                self.activityCache = counts
            }
        }
    }

    private func loadDailyNote(for key: String) -> String {
        let url = AppState.dataDirectory
            .appendingPathComponent("memory")
            .appendingPathComponent("\(key).md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func currentWeeklyKey() -> String? {
        let cal = Calendar(identifier: .iso8601)
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        guard let y = comps.yearForWeekOfYear, let w = comps.weekOfYear else { return nil }
        let key = String(format: "%04d-W%02d", y, w)
        let url = AppState.dataDirectory
            .appendingPathComponent("memory")
            .appendingPathComponent("weekly")
            .appendingPathComponent("\(key).md")
        return FileManager.default.fileExists(atPath: url.path) ? key : nil
    }

    private func loadWeeklyReport(_ key: String) {
        let url = AppState.dataDirectory
            .appendingPathComponent("memory")
            .appendingPathComponent("weekly")
            .appendingPathComponent("\(key).md")
        weeklyReport = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        showWeeklyReport = true
        selectedDay = nil
    }
}
