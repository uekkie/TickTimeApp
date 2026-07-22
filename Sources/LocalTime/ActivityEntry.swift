import Foundation

struct ActivityEntry: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let appName: String
    let bundleIdentifier: String
    let windowTitle: String?
    let project: String?
    let repository: String?
    let branch: String?
    let language: String?
    let entity: String?
    let source: ActivitySource?
    var heartbeatIDs: [UUID]?
    let startedAt: Date
    var endedAt: Date

    init(
        id: UUID = UUID(),
        appName: String,
        bundleIdentifier: String,
        windowTitle: String? = nil,
        project: String? = nil,
        repository: String? = nil,
        branch: String? = nil,
        language: String? = nil,
        entity: String? = nil,
        source: ActivitySource? = .application,
        heartbeatIDs: [UUID]? = nil,
        startedAt: Date,
        endedAt: Date
    ) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.project = project
        self.repository = repository
        self.branch = branch
        self.language = language
        self.entity = entity
        self.source = source
        self.heartbeatIDs = heartbeatIDs
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }
}

enum ActivitySource: String, Codable, Equatable, Sendable {
    case application
    case vscode
}

struct DayDuration: Identifiable, Equatable, Sendable {
    let date: Date
    let duration: TimeInterval

    var id: Date { date }
}

struct ProjectDuration: Identifiable, Equatable, Sendable {
    let project: String
    let repository: String
    let duration: TimeInterval

    var id: String { repository }
}

struct EditorHeartbeat: Codable, Equatable, Sendable {
    let id: UUID
    let editor: String
    let project: String
    let repository: String
    let branch: String?
    let language: String?
    let entity: String?
    let occurredAt: Date
    let durationSeconds: TimeInterval
}
