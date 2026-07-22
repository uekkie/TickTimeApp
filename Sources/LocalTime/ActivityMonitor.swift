import Combine
import CoreGraphics
import Foundation

@MainActor
final class ActivityMonitor: ObservableObject {
    @Published private(set) var currentProjectName: String?
    @Published private(set) var isIdle = false
    @Published private(set) var now = Date()

    private let store: ActivityStore
    private let settings: TrackingSettings
    private var timer: Timer?

    init(store: ActivityStore, settings: TrackingSettings) {
        self.store = store
        self.settings = settings
        start()
    }

    func evaluate(at date: Date = Date()) {
        now = date

        guard settings.isTrackingEnabled else {
            isIdle = false
            currentProjectName = nil
            store.discardPendingHeartbeats(before: date)
            return
        }

        let idleSeconds = Self.systemIdleSeconds()
        isIdle = idleSeconds >= settings.idleThreshold
        store.importPendingHeartbeats(now: date)

        if !isIdle, store.hasRecentEditorHeartbeat(at: date) {
            currentProjectName = store.latestEditorProject
        } else {
            currentProjectName = nil
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluate()
            }
        }
        evaluate()
    }

    private static func systemIdleSeconds() -> TimeInterval {
        let events: [CGEventType] = [
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .mouseMoved,
            .scrollWheel,
            .flagsChanged
        ]
        return events.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }.min() ?? 0
    }
}
