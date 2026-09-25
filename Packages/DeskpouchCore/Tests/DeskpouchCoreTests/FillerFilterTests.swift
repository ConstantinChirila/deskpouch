import Testing
@testable import DeskpouchCore

struct FillerFilterTests {
    let filter = FillerFilter.default

    @Test func stripsSentenceOpener() {
        #expect(filter.clean("Um, so I went to the store.") == "So I went to the store.")
        #expect(filter.clean("Uh so I went.") == "So I went.")
    }

    @Test func stripsMidSentence() {
        #expect(filter.clean("I went, um, to the store.") == "I went to the store.")
        #expect(filter.clean("I went um to the store.") == "I went to the store.")
        #expect(filter.clean("Yes, hmm, maybe.") == "Yes maybe.")
    }

    @Test func movesSentenceEnd() {
        #expect(filter.clean("I think so, um. Next one.") == "I think so. Next one.")
        #expect(filter.clean("I think so um? Next one.") == "I think so? Next one.")
        #expect(filter.clean("Done. Um. Next one.") == "Done. Next one.")
    }

    @Test func handlesRuns() {
        #expect(filter.clean("Um, uh, so, um, yeah.") == "So yeah.")
        #expect(filter.clean("um") == "")
        #expect(filter.clean("Um, uh.") == "")
    }

    @Test func capitalisesAfterSentenceStart() {
        #expect(filter.clean("Done. Um, then we left.") == "Done. Then we left.")
        #expect(filter.clean("Done! Uh, then we left.") == "Done! Then we left.")
    }

    @Test func leavesRealWords() {
        #expect(filter.clean("Oh no, the umbrella is in Birmingham.") == "Oh no, the umbrella is in Birmingham.")
        #expect(filter.clean("Uh-oh, that's an error.") == "Uh-oh, that's an error.")
        #expect(filter.clean("He said 'um' out loud.") == "He said 'um' out loud.")
        #expect(filter.clean("You know, like, whatever.") == "You know, like, whatever.")
    }

    @Test func leavesEnglishWordsThatSoundLikeFillers() {
        #expect(filter.clean("He is in the ER.") == "He is in the ER.")
        #expect(filter.clean("I shot it with a 35 mm lens.") == "I shot it with a 35 mm lens.")
        #expect(filter.clean("Ah, there you are.") == "Ah, there you are.")
    }

    @Test func germanKeepsItsWords() {
        let german = FillerFilter.forLanguage("de")
        #expect(german.clean("Er kommt um fünf.") == "Er kommt um fünf.")
        #expect(german.clean("Äh, er kommt, ähm, um fünf.") == "Er kommt um fünf.")
    }

    @Test func otherLanguagesAreLeftAlone() {
        #expect(FillerFilter.forLanguage("pt").clean("Um café, uh, por favor.") == "Um café, uh, por favor.")
        #expect(FillerFilter.forLanguage(nil).clean("um hello") == "um hello")
        #expect(FillerFilter.forLanguage("en-GB").clean("um hello") == "Hello")
    }

    @Test func caseInsensitive() {
        #expect(filter.clean("UM, so HMM, yes.") == "So yes.")
    }

    @Test func customList() {
        let filter = FillerFilter(fillers: ["oh"])
        #expect(filter.clean("Oh, I see. Um, right.") == "I see. Um, right.")
    }
}
