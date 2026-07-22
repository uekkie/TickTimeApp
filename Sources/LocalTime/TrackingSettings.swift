import Combine
import Foundation

@MainActor
final class TrackingSettings: ObservableObject {
    private enum Key {
        static let isTrackingEnabled = "isTrackingEnabled"
        static let idleThreshold = "idleThreshold"
    }

    private struct ControlState: Codable {
        let trackingEnabled: Bool
        let idleTimeoutSeconds: TimeInterval
    }

    private let defaults: UserDefaults
    private let controlStateURL: URL

    @Published var isTrackingEnabled: Bool {
        didSet {
            defaults.set(isTrackingEnabled, forKey: Key.isTrackingEnabled)
            writeControlState()
        }
    }

    @Published var idleThreshold: TimeInterval {
        didSet {
            defaults.set(idleThreshold, forKey: Key.idleThreshold)
            writeControlState()
        }
    }

    init(
        defaults: UserDefaults = .standard,
        controlStateURL: URL = TrackingSettings.defaultControlStateURL
    ) {
        self.defaults = defaults
        self.controlStateURL = controlStateURL

        if defaults.object(forKey: Key.isTrackingEnabled) == nil {
            isTrackingEnabled = true
        } else {
            isTrackingEnabled = defaults.bool(forKey: Key.isTrackingEnabled)
        }

        let savedIdleThreshold = defaults.double(forKey: Key.idleThreshold)
        idleThreshold = savedIdleThreshold > 0 ? savedIdleThreshold : 120
        writeControlState()
    }

    private func writeControlState() {
        do {
            try FileManager.default.createDirectory(
                at: controlStateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(ControlState(
                trackingEnabled: isTrackingEnabled,
                idleTimeoutSeconds: idleThreshold
            ))
            try data.write(to: controlStateURL, options: .atomic)
        } catch {
            // The app remains usable; the monitor also discards heartbeats while paused.
        }
    }

    static var defaultControlStateURL: URL {
        ActivityStore.defaultFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("control.json")
    }
}
