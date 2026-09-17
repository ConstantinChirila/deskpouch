import Foundation
import Testing
@testable import DeskpouchCore

struct CaptureNamingTests {
    private var utc: TimeZone { TimeZone(identifier: "UTC")! }
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        return c
    }

    @Test func stampedMatchesThePlanFormatExactly() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 14, minute: 5, second: 2))!
        let stamp = CaptureNaming.stamped(prefix: "Screenshot", extension: "png", date: date, timeZone: utc)
        #expect(stamp == "Screenshot 2026-09-16 14.05.02.png")
    }

    @Test func stampedUsesTheGivenTimeZoneNotTheSystemOne() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 0, minute: 30, second: 0))!
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let stamp = CaptureNaming.stamped(prefix: "Recording", extension: "mp4", date: date, timeZone: tokyo)
        // UTC midnight-thirty is 09:30 in Tokyo (UTC+9): a real timezone switch, not just a formatting nicety.
        #expect(stamp == "Recording 2026-09-16 09.30.00.mp4")
    }

    @Test func uniqueReturnsTheURLUnchangedWhenNothingIsThere() {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = folder.appending(path: "Screenshot 2026-09-16 14.05.02.png")
        #expect(CaptureNaming.unique(url) == url)
    }

    @Test func uniqueAddsANumericSuffixWhenTheFileExists() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = folder.appending(path: "Screenshot 2026-09-16 14.05.02.png")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        let first = CaptureNaming.unique(url)
        #expect(first.lastPathComponent == "Screenshot 2026-09-16 14.05.02 2.png")

        FileManager.default.createFile(atPath: first.path, contents: Data())
        let second = CaptureNaming.unique(url)
        #expect(second.lastPathComponent == "Screenshot 2026-09-16 14.05.02 3.png")
    }
}
