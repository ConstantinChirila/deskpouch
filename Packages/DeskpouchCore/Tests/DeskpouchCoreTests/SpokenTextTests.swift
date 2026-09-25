import Testing
@testable import DeskpouchCore

struct SpokenPunctuationTests {
    let spoken = SpokenPunctuation.default

    @Test func replacesMarks() {
        #expect(spoken.apply("Hello comma how are you question mark") == "Hello, how are you?")
        #expect(spoken.apply("Wait exclamation point now") == "Wait! Now")
        #expect(spoken.apply("Two things colon apples semicolon pears full stop") == "Two things: apples; pears.")
    }

    @Test func absorbsTheModelsPunctuation() {
        #expect(spoken.apply("Hello. Comma. How are you? Question mark.") == "Hello, How are you?")
        #expect(spoken.apply("Hello, comma, how are you") == "Hello, how are you")
    }

    @Test func breaksLines() {
        #expect(spoken.apply("Hi team. New line. The build is green") == "Hi team.\nThe build is green")
        #expect(spoken.apply("Hi team, new paragraph, the build is green") == "Hi team\n\nThe build is green")
        #expect(spoken.apply("first new line second newline third") == "first\nSecond\nThird")
    }

    @Test func leavesAmbiguousWordsInProse() {
        #expect(spoken.apply("That was the best period of my life.") == "That was the best period of my life.")
        #expect(spoken.apply("Add a dash of salt.") == "Add a dash of salt.")
        #expect(spoken.apply("I think so, period. Next") == "I think so. Next")
        #expect(spoken.apply("I think so period") == "I think so.")
    }

    @Test func leavesCommandsThatAreTalkedAbout() {
        #expect(spoken.apply("He has colon cancer.") == "He has colon cancer.")
        #expect(spoken.apply("Use the Oxford comma here.") == "Use the Oxford comma here.")
        #expect(spoken.apply("That is a big question mark for me.") == "That is a big question mark for me.")
        #expect(spoken.apply("We start a new line of products.") == "We start a new line of products.")
        #expect(spoken.apply("Add a comma and a full stop.") == "Add a comma and a full stop.")
        #expect(spoken.apply("I saw the dog comma then I ran full stop") == "I saw the dog, then I ran.")
    }

    @Test func ignoresPartsOfWords() {
        #expect(spoken.apply("The commander spoke.") == "The commander spoke.")
    }

    @Test func dropsACommandWithNothingBefore() {
        #expect(spoken.apply("Comma hello") == "Hello")
    }

    @Test func leavesPlainTextAlone() {
        #expect(spoken.apply("Nothing to see here.") == "Nothing to see here.")
    }
}

struct WordReplacementsTests {
    @Test func replacesWholeWordsAnyCase() {
        let rules = WordReplacements([WordReplacement(heard: "desk pouch", written: "Deskpouch")])
        #expect(rules.apply("I built Desk  Pouch, and desk pouch works.") == "I built Deskpouch, and Deskpouch works.")
        #expect(rules.apply("desk pouches") == "desk pouches")
    }

    @Test func longerEntriesWin() {
        let rules = WordReplacements([
            WordReplacement(heard: "swift", written: "Swift"),
            WordReplacement(heard: "swift ui", written: "SwiftUI"),
        ])
        #expect(rules.apply("swift ui and swift") == "SwiftUI and Swift")
    }

    @Test func keepsSpecialCharactersLiteral() {
        let rules = WordReplacements([WordReplacement(heard: "c plus plus", written: "C++ ($1)")])
        #expect(rules.apply("I write c plus plus.") == "I write C++ ($1).")
    }

    @Test func skipsBlankEntries() {
        #expect(WordReplacements([WordReplacement(heard: "  ", written: "x")]).isEmpty)
    }
}

struct SpokenSendTests {
    @Test func stripsAClosingSend() {
        #expect(SpokenSend.parse("See you at five. Send.") == .init(text: "See you at five.", submit: true))
        #expect(SpokenSend.parse("Are you in? send") == .init(text: "Are you in?", submit: true))
    }

    @Test func aLoneSendSubmitsNothing() {
        #expect(SpokenSend.parse("Send.") == .init(text: "", submit: true))
    }

    @Test func leavesProse() {
        #expect(SpokenSend.parse("Then press send.") == .init(text: "Then press send.", submit: false))
        #expect(SpokenSend.parse("Send it to me.") == .init(text: "Send it to me.", submit: false))
        #expect(SpokenSend.parse("We will resend.") == .init(text: "We will resend.", submit: false))
    }
}

struct SpokenNumbersTests {
    let numbers = SpokenNumbers.default

    @Test func convertsCardinals() {
        #expect(numbers.apply("There are forty two people.") == "There are 42 people.")
        #expect(numbers.apply("two hundred and five rows") == "205 rows")
        #expect(numbers.apply("one thousand two hundred people") == "1,200 people")
        #expect(numbers.apply("Twenty-five of them, ten of us") == "25 of them, 10 of us")
        #expect(numbers.apply("three million views and two thousand likes") == "3 million views and 2,000 likes")
        #expect(numbers.apply("five million two hundred thousand") == "5,200,000")
    }

    @Test func leavesSmallNumbersAndProse() {
        #expect(numbers.apply("I have one idea and two problems.") == "I have one idea and two problems.")
        #expect(numbers.apply("No one came, not a hundred, and so on.") == "No one came, not a hundred, and so on.")
        #expect(numbers.apply("Call five five five one two.") == "Call five five five one two.")
    }

    @Test func doesNotJoinAcrossPunctuation() {
        #expect(numbers.apply("I counted twenty, five times.") == "I counted 20, five times.")
    }

    @Test func money() {
        #expect(numbers.apply("It costs two hundred thirty two dollars and fifty cents.") == "It costs $232.50.")
        #expect(numbers.apply("five dollars, or ten euros") == "$5, or €10")
        #expect(numbers.apply("one dollar five cents") == "$1.05")
        #expect(numbers.apply("five dollars and a coffee") == "$5 and a coffee")
    }

    @Test func times() {
        #expect(numbers.apply("Meet me at three thirty PM.") == "Meet me at 3:30 PM.")
        #expect(numbers.apply("at nine am or twelve oh five pm") == "at 9 AM or 12:05 PM")
    }

    @Test func theVerbAmIsNotATime() {
        #expect(numbers.apply("Which one am I supposed to use?") == "Which one am I supposed to use?")
        #expect(numbers.apply("The one am I thinking of") == "The one am I thinking of")
        #expect(numbers.apply("At nine am I left.") == "At 9 AM I left.")
        #expect(numbers.apply("Wake me at one am.") == "Wake me at 1 AM.")
    }

    @Test func percentAndDecimals() {
        #expect(numbers.apply("five percent of version two point five") == "5% of version 2.5")
        #expect(numbers.apply("up three point oh five percent") == "up 3.05%")
    }

    @Test func years() {
        #expect(numbers.apply("back in nineteen ninety nine and twenty twenty five") == "back in 1999 and 2025")
    }

    @Test func ordinals() {
        #expect(numbers.apply("She came twenty first, he came first.") == "She came 21st, he came first.")
        #expect(numbers.apply("the twenty second of May") == "the 22nd of May")
        #expect(numbers.apply("a twenty second delay") == "a twenty second delay")
        #expect(numbers.apply("the twelfth floor, the two hundredth visitor") == "the 12th floor, the 200th visitor")
    }

    @Test func leavesLookalikesAlone() {
        #expect(numbers.apply("a fifty fifty chance") == "a fifty fifty chance")
        #expect(numbers.apply("We are open twenty four seven.") == "We are open twenty four seven.")
        #expect(numbers.apply("Open twenty-four seven, all fifty states.") == "Open twenty-four seven, all 50 states.")
        #expect(numbers.apply("ten twenty dollar bills") == "10 $20 bills")
        #expect(numbers.apply("At one point five of us left.") == "At one point five of us left.")
    }

    @Test func spokenYearsTakeNoComma() {
        #expect(numbers.apply("since two thousand twenty five") == "since 2025")
        #expect(numbers.apply("in twenty twenty") == "in 2020")
        #expect(numbers.apply("three thousand twenty five rows") == "3,025 rows")
    }

    @Test func leavesDigitsAlone() {
        #expect(numbers.apply("We need 25% more by January 5th, 2025.") == "We need 25% more by January 5th, 2025.")
    }
}
