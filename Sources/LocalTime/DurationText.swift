import Foundation

enum DurationText {
    static func compact(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60

        if hours > 0 { return "\(hours)時間 \(minutes)分" }
        if minutes > 0 { return "\(minutes)分" }
        return "\(seconds)秒"
    }
}
