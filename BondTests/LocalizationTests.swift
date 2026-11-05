import Foundation
import Testing

@testable import Bond

/// The string catalog compiles into one .lproj per language, and the plural
/// rules survive the trip. A key that fell back to English would still pass a
/// "not empty" check, so these compare against the catalog's own wording.
/// Add each language to `languages` when its translations land.
@Suite("Localization")
struct LocalizationTests {
    static let languages = ["en"]

    private func bundle(_ language: String) -> Bundle? {
        let hosts = [Bundle.main] + Bundle.allBundles
        for host in hosts {
            if let path = host.path(forResource: language, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return nil
    }

    @Test func everyLanguageShips() {
        for language in Self.languages {
            #expect(bundle(language) != nil, "\(language).lproj is missing")
        }
    }

    @Test func englishPluralsPickTheRightForm() throws {
        let en = try #require(bundle("en"))
        let locale = Locale(identifier: "en")
        #expect(String(localized: "\(1) reminders", bundle: en, locale: locale) == "1 reminder")
        #expect(String(localized: "\(3) reminders", bundle: en, locale: locale) == "3 reminders")
        #expect(String(localized: "Add \(1) reminders", bundle: en, locale: locale) == "Add 1 reminder")
        #expect(String(localized: "Add \(4) reminders", bundle: en, locale: locale) == "Add 4 reminders")
    }

    @Test func pluralCategoryFollowsTheLanguage() throws {
        let en = try #require(bundle("en"))
        let locale = Locale(identifier: "en")
        #expect(String(localized: "\(1) plural category", bundle: en, locale: locale) == "one 1")
        #expect(String(localized: "\(5) plural category", bundle: en, locale: locale) == "other 5")
        #expect(PluralLabel.category(1) == .one)
        #expect(PluralLabel.category(12) == .other)
        #expect(PluralLabel.daysToGo(1) == "day to go")
        #expect(PluralLabel.daysToGo(12) == "days to go")
        #expect(PluralLabel.dayStreak(12) == "day streak")
    }

    @Test func trialLabelsKeepTheirWording() throws {
        let en = try #require(bundle("en"))
        let locale = Locale(identifier: "en")
        #expect(String(localized: "\(7)-day free trial", bundle: en, locale: locale) == "7-day free trial")
        #expect(String(localized: "\(1)-Month Free Trial", bundle: en, locale: locale) == "1-Month Free Trial")
    }

    @Test func modelTitlesComeFromTheCatalog() {
        #expect(LoveLanguage.words.title == "Words of Affirmation")
        #expect(RecurrencePreset.weekly.title == "Every week")
        #expect(MilestoneDTO.kindTitle("anniversary") == "Anniversary")
        #expect(MilestoneDTO.kindTitle("custom") == "Custom")
        #expect(LoveLanguage.touch.leastExpressedInsight.hasPrefix("Physical Touch is your least expressed"))
    }

    @Test func templatesAreRebuiltFromTheCatalog() {
        let groups = ReminderTemplateStore.groups
        #expect(groups.count == 6)
        #expect(groups.first?.title == "Daily Affirmations")
    }
}
