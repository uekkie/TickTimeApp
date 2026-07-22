import SwiftUI

@main
struct TickTimeApp: App {
    @StateObject private var store: ActivityStore
    @StateObject private var settings: TrackingSettings
    @StateObject private var monitor: ActivityMonitor

    init() {
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
        WindowGroup("TickTime", id: "dashboard") {
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
