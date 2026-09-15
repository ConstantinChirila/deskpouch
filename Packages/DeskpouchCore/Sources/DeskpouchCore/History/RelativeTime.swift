import Foundation

public enum RelativeTime {
    /// "just now", "2 min ago", "1 hr ago", "yesterday", "3 days ago", then a short date.
    public static func phrase(from date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return hours == 1 ? "1 hr ago" : "\(hours) hrs ago" }
        let days = hours / 24
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days) days ago" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
