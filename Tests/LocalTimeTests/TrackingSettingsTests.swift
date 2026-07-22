import Foundation
import Testing
@testable import TickTime

@MainActor
struct TrackingSettingsTests {
    @Test func writesSharedControlStateForTheVSCodeExtension() throws {
        let suiteName = "TrackingSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("control.json")
        let settings = TrackingSettings(defaults: defaults, controlStateURL: stateURL)

        settings.isTrackingEnabled = false
        settings.idleThreshold = 300

        let object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        #expect(object["trackingEnabled"] as? Bool == false)
        #expect(object["idleTimeoutSeconds"] as? Double == 300)
    }
}
