import AppKit
import SwiftUI

@main
struct TickTimeApp: App {
    @StateObject private var store: ActivityStore
    @StateObject private var settings: TrackingSettings
    @StateObject private var monitor: ActivityMonitor

    init() {
        SingleInstanceGuard.terminateIfAlreadyRunning()

        let store = ActivityStore()
        let settings = TrackingSettings()
        _store = StateObject(wrappedValue: store)
        _settings = StateObject(wrappedValue: settings)
        _monitor = StateObject(wrappedValue: ActivityMonitor(
            store: store,
            settings: settings
        ))
    }

    var body: some Scene {
        Window("TickTime", id: "dashboard") {
            DashboardView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(monitor)
        }
        .defaultSize(width: 960, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(monitor)
        } label: {
            Image(systemName: monitor.currentProjectName == nil ? "clock" : "clock.fill")
                .accessibilityLabel("TickTime")
        }
        .menuBarExtraStyle(.window)
    }
}

/// 二重起動を防ぐためのガード。
/// すでに同じアプリが起動している場合は、そのインスタンスを前面に出して自身を終了する。
enum SingleInstanceGuard {
    static func terminateIfAlreadyRunning() {
        let current = NSRunningApplication.current
        let currentPID = current.processIdentifier

        let others: [NSRunningApplication]
        if let bundleID = Bundle.main.bundleIdentifier {
            // .app バンドルとして起動された場合は Bundle ID で判定する。
            others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != currentPID }
        } else if let executableURL = current.executableURL {
            // `swift run` など Bundle ID を持たない起動でも実行ファイルパスで判定する。
            others = NSWorkspace.shared.runningApplications.filter {
                $0.processIdentifier != currentPID && $0.executableURL == executableURL
            }
        } else {
            others = []
        }

        guard let existing = others.first else { return }

        // すでに起動しているインスタンスを前面に出して、自分は終了する。
        existing.activate(options: [.activateAllWindows])
        exit(0)
    }
}
