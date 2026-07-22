import Foundation

enum ActivityAnalytics {
    static func duration(
        of entries: [ActivityEntry],
        from start: Date,
        to end: Date
    ) -> TimeInterval {
        guard start < end else { return 0 }

        let intervals = entries.compactMap { entry -> DateInterval? in
            let overlapStart = max(start, entry.startedAt)
            let overlapEnd = min(end, entry.endedAt)
            guard overlapStart < overlapEnd else { return nil }
            return DateInterval(start: overlapStart, end: overlapEnd)
        }
        .sorted { $0.start < $1.start }

        guard var current = intervals.first else { return 0 }
        var total: TimeInterval = 0

        for interval in intervals.dropFirst() {
            if interval.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                total += current.duration
                current = interval
            }
        }

        return total + current.duration
    }

    static func durationByProject(
        of entries: [ActivityEntry],
        from start: Date,
        to end: Date
    ) -> [ProjectDuration] {
        let projectEntries = Dictionary(grouping: entries.compactMap { entry -> ActivityEntry? in
            guard entry.project != nil, entry.repository != nil else { return nil }
            return entry
        }) { $0.repository ?? "" }

        return projectEntries.compactMap { repository, entries in
            guard let project = entries.first?.project else { return nil }
            return ProjectDuration(
                project: project,
                repository: repository,
                duration: duration(of: entries, from: start, to: end)
            )
        }
        .filter { $0.duration > 0 }
        .sorted { lhs, rhs in
            if lhs.duration == rhs.duration {
                return lhs.project.localizedStandardCompare(rhs.project) == .orderedAscending
            }
            return lhs.duration > rhs.duration
        }
    }

    static func dailyTotals(
        of entries: [ActivityEntry],
        endingOn endDate: Date,
        dayCount: Int,
        calendar: Calendar = .current
    ) -> [DayDuration] {
        guard dayCount > 0 else { return [] }

        let endDay = calendar.startOfDay(for: endDate)
        return (0..<dayCount).reversed().compactMap { offset in
            guard
                let day = calendar.date(byAdding: .day, value: -offset, to: endDay),
                let nextDay = calendar.date(byAdding: .day, value: 1, to: day)
            else { return nil }

            return DayDuration(
                date: day,
                duration: duration(of: entries, from: day, to: nextDay)
            )
        }
    }
}
