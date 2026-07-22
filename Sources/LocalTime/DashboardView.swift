import AppKit
import Charts
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: ActivityStore
    @EnvironmentObject private var settings: TrackingSettings
    @EnvironmentObject private var monitor: ActivityMonitor

    @State private var showingClearConfirmation = false

    private var allEntries: [ActivityEntry] {
        store.entries.filter { $0.project != nil && $0.repository != nil }
    }

    private var todayInterval: (start: Date, end: Date) {
        let start = Calendar.current.startOfDay(for: monitor.now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? monitor.now
        return (start, end)
    }

    private var todayDuration: TimeInterval {
        ActivityAnalytics.duration(
            of: allEntries,
            from: todayInterval.start,
            to: todayInterval.end
        )
    }

    private var todayProjects: [ProjectDuration] {
        ActivityAnalytics.durationByProject(
            of: allEntries,
            from: todayInterval.start,
            to: todayInterval.end
        )
    }

    private var lastSevenDays: [DayDuration] {
        ActivityAnalytics.dailyTotals(
            of: allEntries,
            endingOn: monitor.now,
            dayCount: 7
        )
    }

    private var sevenDayDuration: TimeInterval {
        lastSevenDays.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                statusCards

                HStack(alignment: .top, spacing: 18) {
                    weeklyChart
                    appBreakdown
                }

                recentActivity
                settingsPanel
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 880, minHeight: 700)
        .alert("計測履歴を削除しますか？", isPresented: $showingClearConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("すべて削除", role: .destructive) {
                store.clearHistory(at: monitor.now)
            }
        } message: {
            Text("この操作は取り消せません。設定は残ります。")
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TickTime")
                    .font(.largeTitle.weight(.bold))
                Text("作業時間は、このMacの中だけに保存されます")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle(isOn: $settings.isTrackingEnabled) {
                Text(settings.isTrackingEnabled ? "計測中" : "一時停止中")
                    .fontWeight(.semibold)
            }
            .toggleStyle(.switch)
        }
    }

    private var statusCards: some View {
        HStack(spacing: 14) {
            StatCard(
                title: "今日",
                value: DurationText.compact(todayDuration),
                detail: todayProjects.isEmpty ? "リポジトリの記録待ち" : "\(todayProjects.count)個のリポジトリ",
                systemImage: "clock.fill",
                color: .indigo
            )

            StatCard(
                title: "直近7日",
                value: DurationText.compact(sevenDayDuration),
                detail: "1日平均 \(DurationText.compact(sevenDayDuration / 7))",
                systemImage: "calendar",
                color: .blue
            )

            StatCard(
                title: "現在",
                value: currentStatusTitle,
                detail: currentStatusDetail,
                systemImage: monitor.currentProjectName == nil ? "pause.fill" : "record.circle",
                color: monitor.currentProjectName == nil ? .secondary : .green
            )
        }
    }

    private var currentStatusTitle: String {
        if !settings.isTrackingEnabled { return "停止中" }
        if monitor.isIdle { return "離席中" }
        return monitor.currentProjectName ?? "待機中"
    }

    private var currentStatusDetail: String {
        if monitor.currentProjectName != nil { return "VS Codeから記録しています" }
        return "VS Codeでリポジトリを開くと開始します"
    }

    private var weeklyChart: some View {
        Panel(title: "直近7日の作業時間", systemImage: "chart.bar.fill") {
            Chart(lastSevenDays) { day in
                BarMark(
                    x: .value("日", day.date, unit: .day),
                    y: .value("時間", day.duration / 3_600)
                )
                .foregroundStyle(
                    day.date == Calendar.current.startOfDay(for: monitor.now)
                        ? Color.indigo.gradient
                        : Color.blue.opacity(0.55).gradient
                )
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                    AxisTick()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hours = value.as(Double.self) {
                            Text("\(hours, specifier: "%.1f")h")
                        }
                    }
                }
            }
            .frame(height: 220)
        }
        .frame(maxWidth: .infinity)
    }

    private var appBreakdown: some View {
        Panel(title: "今日のリポジトリ", systemImage: "externaldrive.connected.to.line.below.fill") {
            if todayProjects.isEmpty {
                ContentUnavailableView(
                    "まだ記録がありません",
                    systemImage: "shippingbox",
                    description: Text("VS Code拡張機能を入れると、ここに内訳が表示されます")
                )
                .frame(height: 220)
            } else {
                VStack(spacing: 14) {
                    ForEach(todayProjects.prefix(5)) { project in
                        ProjectDurationRow(
                            project: project,
                            longestDuration: todayProjects.first?.duration ?? 1
                        )
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 220, alignment: .top)
            }
        }
        .frame(width: 340)
    }

    private var recentActivity: some View {
        Panel(title: "最近の記録", systemImage: "list.bullet") {
            let recent = allEntries.sorted { $0.startedAt > $1.startedAt }

            if recent.isEmpty {
                Text("記録が始まると、ここにセッションが並びます。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.prefix(8).enumerated()), id: \.element.id) { index, entry in
                        RecentActivityRow(entry: entry)
                        if index < min(recent.count, 8) - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var settingsPanel: some View {
        Panel(title: "設定", systemImage: "gearshape.fill") {
            VStack(spacing: 16) {
                HStack {
                    Text("離席とみなす時間")
                    Spacer()
                    Picker("離席とみなす時間", selection: $settings.idleThreshold) {
                        Text("1分").tag(TimeInterval(60))
                        Text("2分").tag(TimeInterval(120))
                        Text("5分").tag(TimeInterval(300))
                        Text("10分").tag(TimeInterval(600))
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                Divider()
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("保存先")
                        Text(store.fileURL.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("履歴を削除", role: .destructive) {
                        showingClearConfirmation = true
                    }
                }

                if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 92)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

private struct Panel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

private struct ProjectDurationRow: View {
    let project: ProjectDuration
    let longestDuration: TimeInterval

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.indigo)
                    .frame(width: 24, height: 24)
                Text(project.project)
                    .lineLimit(1)
                Spacer()
                Text(DurationText.compact(project.duration))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.indigo.gradient)
                            .frame(width: geometry.size.width * project.duration / max(1, longestDuration))
                    }
            }
            .frame(height: 5)
        }
    }
}

private struct RecentActivityRow: View {
    let entry: ActivityEntry

    var body: some View {
        HStack(spacing: 12) {
            ApplicationIcon(bundleIdentifier: entry.bundleIdentifier)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.project ?? entry.appName)
                    .fontWeight(.medium)
                if let detail = detailText {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(entry.startedAt.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(DurationText.compact(entry.duration))
                .font(.callout.monospacedDigit())
                .frame(width: 84, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }

    private var detailText: String? {
        if let entity = entry.entity {
            let branch = entry.branch.map { " · \($0)" } ?? ""
            return "\(entity)\(branch)"
        }
        return entry.windowTitle
    }
}

private struct ApplicationIcon: View {
    let bundleIdentifier: String

    var body: some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(4)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 24, height: 24)
    }
}
