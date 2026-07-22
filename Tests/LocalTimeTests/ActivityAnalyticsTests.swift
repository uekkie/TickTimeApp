import Foundation
import Testing
@testable import TickTime

struct ActivityAnalyticsTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test func durationClipsEntriesAtRangeBoundaries() throws {
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 22, hour: 9
        )))
        let entries = [
            entry(app: "Xcode", bundle: "com.apple.dt.Xcode", start: start - 600, end: start + 1_800),
            entry(app: "Terminal", bundle: "com.apple.Terminal", start: start + 3_000, end: start + 4_200)
        ]

        let result = ActivityAnalytics.duration(
            of: entries,
            from: start,
            to: start + 3_600
        )

        #expect(result == 2_400)
    }

    @Test func totalDurationDoesNotDoubleCountOverlappingSources() throws {
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 22, hour: 9
        )))
        let entries = [
            entry(app: "Visual Studio Code", bundle: "com.microsoft.VSCode", start: start, end: start + 60),
            ActivityEntry(
                appName: "Visual Studio Code",
                bundleIdentifier: "com.microsoft.VSCode",
                project: "TickTime",
                repository: "/code/TickTime",
                source: .vscode,
                startedAt: start + 30,
                endedAt: start + 90
            )
        ]

        let result = ActivityAnalytics.duration(of: entries, from: start, to: start + 120)

        #expect(result == 90)
    }

    @Test func projectTotalsGroupHeartbeatsByRepository() throws {
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 22, hour: 9
        )))
        let entries = [
            ActivityEntry(
                appName: "Visual Studio Code",
                bundleIdentifier: "com.microsoft.VSCode",
                project: "TickTime",
                repository: "/code/TickTime",
                source: .vscode,
                startedAt: start,
                endedAt: start + 30
            ),
            ActivityEntry(
                appName: "Visual Studio Code",
                bundleIdentifier: "com.microsoft.VSCode",
                project: "website",
                repository: "/code/website",
                source: .vscode,
                startedAt: start + 30,
                endedAt: start + 90
            )
        ]

        let result = ActivityAnalytics.durationByProject(
            of: entries,
            from: start,
            to: start + 120
        )

        #expect(result.map(\.project) == ["website", "TickTime"])
        #expect(result.map(\.duration) == [60, 30])
    }

    @Test func dailyTotalsSplitAnEntryAcrossMidnight() throws {
        let day = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 22
        )))
        let entryStart = day - 1_800
        let entries = [entry(
            app: "Xcode",
            bundle: "com.apple.dt.Xcode",
            start: entryStart,
            end: day + 1_800
        )]

        let result = ActivityAnalytics.dailyTotals(
            of: entries,
            endingOn: day,
            dayCount: 2,
            calendar: calendar
        )

        #expect(result.map(\.duration) == [1_800, 1_800])
    }

    private func entry(
        app: String,
        bundle: String,
        start: Date,
        end: Date
    ) -> ActivityEntry {
        ActivityEntry(
            appName: app,
            bundleIdentifier: bundle,
            startedAt: start,
            endedAt: end
        )
    }
}
