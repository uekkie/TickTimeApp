import Foundation
import Testing
@testable import TickTime

@MainActor
struct ActivityStoreTests {
    @Test func persistsAndReloadsEntries() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("activity.json")
        let store = ActivityStore(fileURL: fileURL)
        let start = Date(timeIntervalSince1970: 1_000)

        store.append(ActivityEntry(
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            startedAt: start,
            endedAt: start + 30
        ))

        let reloaded = ActivityStore(fileURL: fileURL)
        #expect(reloaded.entries.count == 1)
        #expect(reloaded.entries.first?.duration == 30)
    }

    @Test func importsVSCodeHeartbeatAndRemovesInboxFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = directory.appendingPathComponent("inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let store = ActivityStore(
            fileURL: directory.appendingPathComponent("activity.json"),
            heartbeatInboxURL: inbox
        )
        let heartbeat = EditorHeartbeat(
            id: UUID(),
            editor: "Visual Studio Code",
            project: "TickTime",
            repository: "/code/TickTime",
            branch: "main",
            language: "swift",
            entity: "Sources/App.swift",
            occurredAt: Date(timeIntervalSince1970: 2_000),
            durationSeconds: 15
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let inboxFile = inbox.appendingPathComponent("heartbeat.json")
        try encoder.encode(heartbeat).write(to: inboxFile)

        store.importPendingHeartbeats(now: Date(timeIntervalSince1970: 2_015))

        let entry = try #require(store.entries.first)
        #expect(entry.project == "TickTime")
        #expect(entry.repository == "/code/TickTime")
        #expect(entry.branch == "main")
        #expect(entry.language == "swift")
        #expect(entry.entity == "Sources/App.swift")
        #expect(entry.source == .vscode)
        #expect(entry.duration == 15)
        #expect(FileManager.default.fileExists(atPath: inboxFile.path) == false)
    }

    @Test func keepsInboxFileWhenHistoryCannotBePersisted() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blockingFile = directory.appendingPathComponent("not-a-directory")
        try Data("blocked".utf8).write(to: blockingFile)
        let inbox = directory.appendingPathComponent("inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let store = ActivityStore(
            fileURL: blockingFile.appendingPathComponent("activity.json"),
            heartbeatInboxURL: inbox
        )
        let inboxFile = try writeHeartbeat(
            to: inbox,
            id: UUID(),
            occurredAt: Date(timeIntervalSince1970: 3_000)
        )

        store.importPendingHeartbeats(now: Date(timeIntervalSince1970: 3_015))

        #expect(store.entries.isEmpty)
        #expect(FileManager.default.fileExists(atPath: inboxFile.path))
        #expect(store.lastError != nil)
    }

    @Test func doesNotOverwriteUnreadableHistory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("activity.json")
        let originalData = Data("not json".utf8)
        try originalData.write(to: fileURL)
        let store = ActivityStore(fileURL: fileURL)

        store.append(ActivityEntry(
            appName: "Visual Studio Code",
            bundleIdentifier: "com.microsoft.VSCode",
            project: "TickTime",
            repository: "/code/TickTime",
            source: .vscode,
            startedAt: Date(timeIntervalSince1970: 4_000),
            endedAt: Date(timeIntervalSince1970: 4_015)
        ))

        #expect(try Data(contentsOf: fileURL) == originalData)
        #expect(store.lastError != nil)
    }

    @Test func importsHeartbeatsInTimeOrderAndMergesIDs() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = directory.appendingPathComponent("inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let store = ActivityStore(
            fileURL: directory.appendingPathComponent("activity.json"),
            heartbeatInboxURL: inbox
        )
        _ = try writeHeartbeat(
            to: inbox,
            id: UUID(),
            occurredAt: Date(timeIntervalSince1970: 5_015),
            filename: "a-later.json"
        )
        _ = try writeHeartbeat(
            to: inbox,
            id: UUID(),
            occurredAt: Date(timeIntervalSince1970: 5_000),
            filename: "z-earlier.json"
        )

        store.importPendingHeartbeats(now: Date(timeIntervalSince1970: 5_030))

        let entry = try #require(store.entries.first)
        #expect(store.entries.count == 1)
        #expect(entry.startedAt == Date(timeIntervalSince1970: 5_000))
        #expect(entry.endedAt == Date(timeIntervalSince1970: 5_030))
        #expect(Set(entry.heartbeatIDs ?? []).count == 2)
    }

    @Test func clipsHeartbeatsAtPersistedPauseCutoff() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = directory.appendingPathComponent("inbox", isDirectory: true)
        let cutoffFile = directory.appendingPathComponent("heartbeat-cutoff.json")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("activity.json")
        var store: ActivityStore? = ActivityStore(
            fileURL: fileURL,
            heartbeatInboxURL: inbox,
            heartbeatCutoffURL: cutoffFile
        )
        store?.discardPendingHeartbeats(before: Date(timeIntervalSince1970: 6_010))
        store = nil
        _ = try writeHeartbeat(
            to: inbox,
            id: UUID(),
            occurredAt: Date(timeIntervalSince1970: 6_000)
        )

        let reloaded = ActivityStore(
            fileURL: fileURL,
            heartbeatInboxURL: inbox,
            heartbeatCutoffURL: cutoffFile
        )
        reloaded.importPendingHeartbeats(now: Date(timeIntervalSince1970: 6_015))

        let entry = try #require(reloaded.entries.first)
        #expect(entry.startedAt == Date(timeIntervalSince1970: 6_010))
        #expect(entry.duration == 5)
    }

    @Test func quarantinesUnreadableInboxFiles() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = directory.appendingPathComponent("inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let brokenFile = inbox.appendingPathComponent("broken.json")
        try Data("not json".utf8).write(to: brokenFile)
        let store = ActivityStore(
            fileURL: directory.appendingPathComponent("activity.json"),
            heartbeatInboxURL: inbox
        )

        store.importPendingHeartbeats(now: Date(timeIntervalSince1970: 7_000))

        let rejected = directory.appendingPathComponent("rejected-heartbeats")
        let quarantinedFiles = try FileManager.default.contentsOfDirectory(
            at: rejected,
            includingPropertiesForKeys: nil
        )
        #expect(FileManager.default.fileExists(atPath: brokenFile.path) == false)
        #expect(quarantinedFiles.count == 1)
        #expect(store.lastError != nil)
    }

    private func writeHeartbeat(
        to inbox: URL,
        id: UUID,
        occurredAt: Date,
        filename: String = "heartbeat.json"
    ) throws -> URL {
        let heartbeat = EditorHeartbeat(
            id: id,
            editor: "Visual Studio Code",
            project: "TickTime",
            repository: "/code/TickTime",
            branch: "main",
            language: "swift",
            entity: "Sources/App.swift",
            occurredAt: occurredAt,
            durationSeconds: 15
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let file = inbox.appendingPathComponent(filename)
        try encoder.encode(heartbeat).write(to: file)
        return file
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TickTimeTests-\(UUID().uuidString)", isDirectory: true)
    }
}
