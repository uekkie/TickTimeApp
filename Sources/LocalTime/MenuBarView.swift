import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: ActivityStore
    @EnvironmentObject private var settings: TrackingSettings
    @EnvironmentObject private var monitor: ActivityMonitor

    private var todayDuration: TimeInterval {
        let entries = store.entries.filter { $0.project != nil && $0.repository != nil }
        let start = Calendar.current.startOfDay(for: monitor.now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? monitor.now
        return ActivityAnalytics.duration(of: entries, from: start, to: end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日の作業時間")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(DurationText.compact(todayDuration))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                }
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
            }

            if let projectName = monitor.currentProjectName {
                Label(projectName, systemImage: "record.circle")
                    .font(.callout)
                    .lineLimit(1)
            } else {
                Label(statusText, systemImage: statusIcon)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("ダッシュボードを開く") {
                openDashboard()
            }
            .keyboardShortcut("d")

            Toggle("計測する", isOn: $settings.isTrackingEnabled)

            Divider()

            Button("TickTimeを終了") {
                monitor.stop()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 250)
    }

    private var statusText: String {
        if !settings.isTrackingEnabled { return "一時停止中" }
        if monitor.isIdle { return "離席中" }
        return "VS Codeを待っています"
    }

    private var statusIcon: String {
        if monitor.isIdle { return "moon.zzz.fill" }
        return settings.isTrackingEnabled ? "clock" : "pause.circle"
    }

    private var statusColor: Color {
        if monitor.currentProjectName != nil { return .green }
        if settings.isTrackingEnabled { return .orange }
        return .secondary
    }

    private func openDashboard() {
        openWindow(id: "dashboard")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
