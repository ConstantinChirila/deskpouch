import Testing
@testable import DeskpouchCapture

struct PickerStyleTests {
    @Test func recordKeepsItsExistingLook() {
        #expect(PickerStyle.record.toolbarLabel == "Record")
        #expect(PickerStyle.record.showsAudioToggles)
    }

    @Test func stillReadsAsACaptureWithNoAudioControls() {
        #expect(PickerStyle.still.toolbarLabel == "Capture")
        #expect(!PickerStyle.still.showsAudioToggles)
        #expect(PickerStyle.still.tint != PickerStyle.record.tint)
    }

    @Test func textSharesTheStillLookForNow() {
        #expect(PickerStyle.text.toolbarLabel == "Capture")
        #expect(!PickerStyle.text.showsAudioToggles)
        #expect(PickerStyle.text.tint == PickerStyle.still.tint)
    }
}
