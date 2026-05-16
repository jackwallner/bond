import Testing

@testable import Bond

struct LoveLanguageTests {
    @Test func allCases_count() {
        #expect(LoveLanguage.allCases.count == 5)
    }

    @Test func titles_matchExpected() {
        #expect(LoveLanguage.words.title == "Words of Affirmation")
        #expect(LoveLanguage.acts.title == "Acts of Service")
        #expect(LoveLanguage.gifts.title == "Receiving Gifts")
        #expect(LoveLanguage.time.title == "Quality Time")
        #expect(LoveLanguage.touch.title == "Physical Touch")
    }

    @Test func symbolNames_areNonEmpty() {
        for lang in LoveLanguage.allCases {
            #expect(!lang.symbolName.isEmpty)
        }
    }

    @Test func allCases_distinctRawValues() {
        let rawValues = LoveLanguage.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }
}
