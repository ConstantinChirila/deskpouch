import Foundation
import Testing
@testable import DeskpouchCore

struct RelativeTimeTests {
    @Test func phrases() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func at(_ secondsAgo: TimeInterval) -> String {
            RelativeTime.phrase(from: now.addingTimeInterval(-secondsAgo), now: now)
        }
        #expect(at(0) == "just now")
        #expect(at(59) == "just now")
        #expect(at(60) == "1 min ago")
        #expect(at(2 * 60 + 30) == "2 min ago")
        #expect(at(60 * 60) == "1 hr ago")
        #expect(at(5 * 3600) == "5 hrs ago")
        #expect(at(30 * 3600) == "yesterday")
        #expect(at(3 * 86400) == "3 days ago")
        #expect(at(30 * 86400).count > 3)
    }
}
