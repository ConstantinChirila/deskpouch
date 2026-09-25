import Foundation
import Testing
@testable import ToolCalendar

struct MeetingLinkTests {
    @Test func googleJoinLineWins() {
        let link = MeetingLink.find(url: nil, location: nil, notes: Fixture.meetNotes)
        #expect(link?.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    /// Step 0: one event had a pasted Meet link as HTML before Google's own line.
    @Test func joinLineBeatsAPastedMeetLinkEarlier() {
        let notes = """
        <a href="https://meet.google.com/iea-jnjj-pqt?hs=224">https://meet.google.com/iea-jnjj-pqt</a><br>
        Join with Google Meet: https://meet.google.com/xif-ogmk-fgt
        """
        #expect(MeetingLink.find(url: nil, location: nil, notes: notes)?.absoluteString == "https://meet.google.com/xif-ogmk-fgt")
    }

    @Test func meetLinkInHTMLNotesWithoutTheJoinLine() {
        let notes = "Agenda<br><a href=\"https://meet.google.com/aaa-bbbb-ccc\">join</a>&nbsp;here"
        #expect(MeetingLink.find(url: nil, location: nil, notes: notes)?.absoluteString == "https://meet.google.com/aaa-bbbb-ccc")
    }

    @Test func meetLinkBeatsAnEarlierOtherLink() {
        let notes = "Watch first: https://www.youtube.com/watch?v=x then https://meet.google.com/aaa-bbbb-ccc"
        #expect(MeetingLink.find(url: nil, location: nil, notes: notes)?.host == "meet.google.com")
    }

    @Test func googleRedirectIsUnwrapped() {
        let notes = "https://www.google.com/url?q=https://meet.google.com/aaa-bbbb-ccc&sa=D"
        #expect(MeetingLink.find(url: nil, location: nil, notes: notes)?.absoluteString == "https://meet.google.com/aaa-bbbb-ccc")
    }

    /// A redirect is only unwrapped to an http(s) target: Join must never open a file, a share or another app's
    /// URL handler that an invite smuggled in behind google.com/url.
    @Test func redirectToANonWebTargetIsNoLink() {
        for target in ["file:///System/Applications/Utilities/Terminal.app", "smb://host/share", "someapp://do-something"] {
            let wrapped = "https://www.google.com/url?q=\(target)"
            #expect(MeetingLink.find(url: nil, location: wrapped, notes: nil) == nil, "\(target)")
            #expect(MeetingLink.find(url: wrapped, location: nil, notes: nil) == nil, "\(target)")
            #expect(MeetingLink.find(url: nil, location: nil, notes: "Join with Google Meet: \(wrapped)") == nil, "\(target)")
        }
        let invite = Fixture.event("Call", Fixture.at(14, 30), other: true, location: "https://www.google.com/url?q=file:///etc/passwd")
        #expect(invite.joinLink == nil)
        #expect(!invite.joinable)
    }

    @Test func otherLinkOnlyFromURLOrLocation() {
        #expect(MeetingLink.find(url: nil, location: "https://zoom.us/j/123", notes: nil)?.host == "zoom.us")
        #expect(MeetingLink.find(url: "https://teams.microsoft.com/l/meetup", location: nil, notes: nil)?.host == "teams.microsoft.com")
        #expect(MeetingLink.find(url: nil, location: nil, notes: "Doc: https://docs.google.com/d/1") == nil)
    }

    @Test func noLink() {
        #expect(MeetingLink.find(url: nil, location: "Grand Central Kitchen, Birmingham", notes: "Bring cake") == nil)
        #expect(MeetingLink.find(url: nil, location: nil, notes: "https://meet.google.com/") == nil)
    }

    @Test func authUserAddedOnceAndOnlyToMeet() throws {
        let meet = try #require(URL(string: "https://meet.google.com/abc-defg-hij"))
        #expect(meet.withAuthUser("me@gmail.com").absoluteString == "https://meet.google.com/abc-defg-hij?authuser=me@gmail.com")
        let already = try #require(URL(string: "https://meet.google.com/abc-defg-hij?authuser=1"))
        #expect(already.withAuthUser("me@gmail.com") == already)
        let zoom = try #require(URL(string: "https://zoom.us/j/1"))
        #expect(zoom.withAuthUser("me@gmail.com") == zoom)
        #expect(meet.withAuthUser(nil) == meet)
        #expect(meet.withAuthUser("Google") == meet)
    }

    @Test func joinNeedsAnotherPerson() {
        let solo = Fixture.event("Bin day!", Fixture.at(8, 30), notes: Fixture.meetNotes)
        #expect(solo.joinLink == nil)
        let call = Fixture.event("Design sync", Fixture.at(14, 30), other: true, notes: Fixture.meetNotes)
        #expect(call.joinLink?.absoluteString == "https://meet.google.com/abc-defg-hij?authuser=me@gmail.com")
        #expect(call.isMeet)
    }

    @Test func shortLocation() {
        let e = Fixture.event("Dinner", Fixture.at(18, 0), location: "Grand Central Kitchen, 7 Stephenson St, Birmingham")
        #expect(e.shortLocation == "Grand Central Kitchen")
        #expect(Fixture.event("Call", Fixture.at(18, 0), location: "https://zoom.us/j/1").shortLocation == nil)
    }
}
