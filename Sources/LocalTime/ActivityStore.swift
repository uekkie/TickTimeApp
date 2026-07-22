import Combine
import Foundation

@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var entries: [ActivityEntry]
    @Published private(set) var lastError: String?
    @Published private(set) var latestEditorHeartbeatAt: Date?
    @Published private(set) var latestEditorProject: String?

    let fileURL: URL
    let heartbeatInboxURL: URL
    let heartbeatCutoffURL: URL

    private var canPersistHistory: Bool
    private var discardHeartbeatsBefore: Date

    init(
        fileURL: URL = ActivityStore.defaultFileURL,
        heartbeatInboxURL: URL? = nil,
        heartbeatCutoffURL: URL? = nil
    ) {
        self.fileURL = fileURL
        self.heartbeatInboxURL = heartbeatInboxURL
            ?? fileURL.deletingLastPathComponent().appendingPathComponent("inbox", isDirectory: true)
        self.heartbeatCutoffURL = heartbeatCutoffURL
            ?? fileURL.deletingLastPathComponent().appendingPathComponent("heartbeat-cutoff.json")
        self.discardHeartbeatsBefore = Self.loadHeartbeatCutoff(
            from: heartbeatCutoffURL
                ?? fileURL.deletingLastPathComponent().appendingPathComponent("heartbeat-cutoff.json")
        )

        switch Self.load(from: fileURL) {
        case .success(let loadedEntries):
            entries = loadedEntries.sorted { $0.startedAt < $1.startedAt }
            lastError = nil
            canPersistHistory = true
        case .failure(let loadError):
            entries = []
            lastError = loadError.message
            canPersistHistory = false
        }

        let latest = entries
            .filter { $0.source == .vscode }
            .max { $0.endedAt < $1.endedAt }
        latestEditorHeartbeatAt = latest?.endedAt
        latestEditorProject = latest?.project
    }

    func append(_ entry: ActivityEntry) {
        guard entry.duration >= 2, canPersistHistory else { return }
        let originalEntries = entries
        entries.append(entry)
        normalizeEntries()
        if !persist() { entries = originalEntries }
    }

    func importPendingHeartbeats(now: Date = Date()) {
        guard canPersistHistory else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: heartbeatInboxURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var decoded: [(url: URL, heartbeat: EditorHeartbeat)] = []

        for file in files where file.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file)
                decoded.append((file, try decoder.decode(EditorHeartbeat.self, from: data)))
            } catch {
                lastError = "VS Codeの記録を読み込めませんでした: \(file.lastPathComponent)"
                quarantineHeartbeat(at: file)
            }
        }
        decoded.sort { $0.heartbeat.occurredAt < $1.heartbeat.occurredAt }

        var knownIDs = Set(entries.flatMap { entry in
            [entry.id] + (entry.heartbeatIDs ?? [])
        })
        let originalEntries = entries
        let originalLatestAt = latestEditorHeartbeatAt
        let originalLatestProject = latestEditorProject
        var newlyImportedFiles: [URL] = []
        var alreadyPersistedFiles: [URL] = []

        for item in decoded {
            let heartbeat = item.heartbeat
            if knownIDs.contains(heartbeat.id) {
                alreadyPersistedFiles.append(item.url)
                continue
            }

            guard
                heartbeat.durationSeconds >= 2,
                heartbeat.durationSeconds <= 60,
                heartbeat.occurredAt <= now.addingTimeInterval(60)
            else {
                quarantineHeartbeat(at: item.url)
                continue
            }

            let endedAt = min(
                heartbeat.occurredAt.addingTimeInterval(heartbeat.durationSeconds),
                now
            )
            let startedAt = max(heartbeat.occurredAt, discardHeartbeatsBefore)
            guard endedAt.timeIntervalSince(startedAt) >= 2 else {
                alreadyPersistedFiles.append(item.url)
                continue
            }

            entries.append(ActivityEntry(
                id: heartbeat.id,
                appName: heartbeat.editor,
                bundleIdentifier: "com.microsoft.VSCode",
                project: heartbeat.project,
                repository: heartbeat.repository,
                branch: heartbeat.branch,
                language: heartbeat.language,
                entity: heartbeat.entity,
                source: .vscode,
                heartbeatIDs: [heartbeat.id],
                startedAt: startedAt,
                endedAt: endedAt
            ))
            knownIDs.insert(heartbeat.id)
            if endedAt >= latestEditorHeartbeatAt ?? .distantPast {
                latestEditorHeartbeatAt = endedAt
                latestEditorProject = heartbeat.project
            }
            newlyImportedFiles.append(item.url)
        }

        for file in alreadyPersistedFiles {
            try? FileManager.default.removeItem(at: file)
        }
        guard !newlyImportedFiles.isEmpty else { return }

        normalizeEntries()
        if persist() {
            for file in newlyImportedFiles {
                try? FileManager.default.removeItem(at: file)
            }
        } else {
            entries = originalEntries
            latestEditorHeartbeatAt = originalLatestAt
            latestEditorProject = originalLatestProject
        }
    }

    func hasRecentEditorHeartbeat(at date: Date, within seconds: TimeInterval = 45) -> Bool {
        guard let latestEditorHeartbeatAt else { return false }
        return abs(date.timeIntervalSince(latestEditorHeartbeatAt)) <= seconds
    }

    func discardPendingHeartbeats(before cutoff: Date = Date()) {
        discardHeartbeatsBefore = max(discardHeartbeatsBefore, cutoff)
        persistHeartbeatCutoff()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: heartbeatInboxURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for file in files where file.pathExtension == "json" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func clearHistory(at date: Date = Date()) {
        if !canPersistHistory, !backupUnreadableHistory() { return }

        let originalEntries = entries
        entries = []
        if persist() {
            latestEditorHeartbeatAt = nil
            latestEditorProject = nil
            discardPendingHeartbeats(before: date)
        } else {
            entries = originalEntries
        }
    }

    private func normalizeEntries() {
        let sortedEntries = entries.sorted { $0.startedAt < $1.startedAt }
        entries = sortedEntries.reduce(into: []) { normalized, entry in
            guard let lastIndex = normalized.indices.last,
                  canMerge(normalized[lastIndex], with: entry) else {
                normalized.append(entry)
                return
            }

            normalized[lastIndex].endedAt = max(normalized[lastIndex].endedAt, entry.endedAt)
            let identifiers = (normalized[lastIndex].heartbeatIDs ?? [])
                + [entry.id]
                + (entry.heartbeatIDs ?? [])
            normalized[lastIndex].heartbeatIDs = Array(Set(identifiers))
        }
    }

    private func canMerge(_ previous: ActivityEntry, with next: ActivityEntry) -> Bool {
        previous.bundleIdentifier == next.bundleIdentifier
            && previous.project == next.project
            && previous.repository == next.repository
            && previous.branch == next.branch
            && previous.language == next.language
            && previous.entity == next.entity
            && previous.source == next.source
            && next.startedAt.timeIntervalSince(previous.endedAt) <= 5
    }

    @discardableResult
    private func persist() -> Bool {
        guard canPersistHistory else { return false }

        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(entries).write(to: fileURL, options: .atomic)
            lastError = nil
            return true
        } catch {
            lastError = "履歴を保存できませんでした: \(error.localizedDescription)"
            return false
        }
    }

    private func backupUnreadableHistory() -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            canPersistHistory = true
            return true
        }

        let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent(
            "activity-unreadable-\(UUID().uuidString).json"
        )
        do {
            try FileManager.default.moveItem(at: fileURL, to: backupURL)
            canPersistHistory = true
            return true
        } catch {
            lastError = "読み込めない履歴を退避できませんでした: \(error.localizedDescription)"
            return false
        }
    }

    private func quarantineHeartbeat(at file: URL) {
        let rejectedDirectory = heartbeatInboxURL
            .deletingLastPathComponent()
            .appendingPathComponent("rejected-heartbeats", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: rejectedDirectory,
                withIntermediateDirectories: true
            )
            let destination = rejectedDirectory.appendingPathComponent(
                "\(UUID().uuidString)-\(file.lastPathComponent)"
            )
            try FileManager.default.moveItem(at: file, to: destination)
        } catch {
            lastError = "不正なVS Code記録を退避できませんでした: \(file.lastPathComponent)"
        }
    }

    private func persistHeartbeatCutoff() {
        do {
            try FileManager.default.createDirectory(
                at: heartbeatCutoffURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(HeartbeatCutoff(discardBefore: discardHeartbeatsBefore))
                .write(to: heartbeatCutoffURL, options: .atomic)
        } catch {
            lastError = "一時停止位置を保存できませんでした: \(error.localizedDescription)"
        }
    }

    private static func loadHeartbeatCutoff(from fileURL: URL) -> Date {
        guard let data = try? Data(contentsOf: fileURL) else { return .distantPast }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(HeartbeatCutoff.self, from: data).discardBefore)
            ?? .distantPast
    }

    private static func load(from fileURL: URL) -> Result<[ActivityEntry], HistoryLoadError> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .success([])
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return .success(try decoder.decode([ActivityEntry].self, from: data))
        } catch {
            return .failure(HistoryLoadError(message:
                "保存済みの履歴を読み込めません。元ファイルは保護されています。"
            ))
        }
    }

    static var defaultFileURL: URL {
        if let dataDirectory = ProcessInfo.processInfo.environment["TickTime_DATA_DIRECTORY"],
           !dataDirectory.isEmpty {
            return URL(fileURLWithPath: dataDirectory, isDirectory: true)
                .appendingPathComponent("activity.json")
        }

        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("TickTime", isDirectory: true)
            .appendingPathComponent("activity.json")
    }
}

private struct HeartbeatCutoff: Codable {
    let discardBefore: Date
}

private struct HistoryLoadError: Error {
    let message: String
}
