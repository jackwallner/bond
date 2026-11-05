import Foundation
import Testing

@testable import Bond

/// The string catalog compiles into one .lproj per language, and the plural
/// rules survive the trip. A key that fell back to English would still pass a
/// "not empty" check, so these compare against the catalog's own wording.
/// Add each language to `languages` when its translations land.
@Suite("Localization")
struct LocalizationTests {
    static let languages = ["en", "fr", "pt-BR", "es", "ar", "de", "vi", "ru"]

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

    // MARK: Persisted text stays English

    /// A throwaway bundle whose English table maps keys to other text, standing
    /// in for a translated device.
    private func translatedBundle(_ strings: [String: String]) throws -> Bundle {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("l10n-\(UUID().uuidString).bundle")
        let lproj = dir.appendingPathComponent("en.lproj")
        try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
        let table = strings.map { "\"\($0.key)\" = \"\($0.value)\";" }.joined(separator: "\n")
        try table.write(to: lproj.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
        let info: [String: Any] = ["CFBundleIdentifier": "l10n.fixture", "CFBundleDevelopmentRegion": "en"]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: dir.appendingPathComponent("Info.plist"))
        return try #require(Bundle(url: dir))
    }

    @Test func everyTemplateAndChipTextIsACatalogKey() throws {
        let en = try #require(bundle("en"))
        let missing = "\u{1}missing"
        func isKey(_ text: String) -> Bool { en.localizedString(forKey: text, value: missing, table: nil) != missing }
        for group in ReminderTemplateStore.groups {
            for template in group.reminders {
                #expect(isKey(template.title), "\(template.title)")
                #expect(template.body.map(isKey) ?? true, "\(template.body ?? "")")
            }
        }
        for chip in starterChipPool {
            #expect(isKey(chip.title), "\(chip.title)")
        }
    }

    @Test func templatesDisplayTranslatedButPersistEnglish() throws {
        let fixture = try translatedBundle([
            "Morning Affirmation": "Morgen-Zuspruch",
            "Start the day with a loving message": "Beginne den Tag mit einer lieben Nachricht",
        ])
        let template = try #require(ReminderTemplateStore.dailyAffirmations.reminders.first)
        #expect(TemplateReminder.display(template.title, in: fixture) == "Morgen-Zuspruch")
        let body = try #require(template.body)
        #expect(TemplateReminder.display(body, in: fixture) == "Beginne den Tag mit einer lieben Nachricht")
        // What a template writes into a reminder never depends on the language.
        #expect(template.title == "Morning Affirmation")
        #expect(template.body == "Start the day with a loving message")
        #expect(template.displayTitle == template.title)
    }

    @Test @MainActor func starterChipsKeepTheirIdentityAndEnglishTitle() throws {
        let ids = starterChipPool.map(\.id)
        #expect(Set(ids).count == ids.count)
        let first = starterChips(for: .shared).map(\.id)
        let second = starterChips(for: .shared).map(\.id)
        #expect(first == second)
        let chip = try #require(starterChipPool.first { $0.id == "gestures_flowers" })
        #expect(chip.title == "Bring home flowers")
        let fixture = try translatedBundle(["Bring home flowers": "Blumen mitbringen"])
        #expect(TemplateReminder.display(chip.title, in: fixture) == "Blumen mitbringen")
        #expect(chip.title == "Bring home flowers")
    }

    @Test func geofenceLabelStoresEnglishHomeWhateverIsShown() throws {
        let fixture = try translatedBundle(["Home": "Zuhause"])
        #expect(GeofenceLabel.display("Home", in: fixture) == "Zuhause")
        #expect(GeofenceLabel.stored("Zuhause", in: fixture) == "Home")
        #expect(GeofenceLabel.stored("Home", in: fixture) == "Home")
        // A place the user named is kept as typed, both ways.
        #expect(GeofenceLabel.stored("Mum's house", in: fixture) == "Mum's house")
        #expect(GeofenceLabel.display("Mum's house", in: fixture) == "Mum's house")
        #expect(GeofenceLabel.stored("", in: fixture) == "")
        #expect(GeofenceLabel.display(GeofenceLabel.stableDefault) == "Home")
    }

    // MARK: Whole-sentence copy

    @Test func previewNotesAreWholeSentencesPerLanguage() {
        for language in LoveLanguage.allCases {
            #expect(language.firstReminderNote == "Your first \(language.title) reminder.")
            #expect(language.otherRemindersNote(1) == "1 other reminder speaks \(language.title).")
            #expect(language.otherRemindersNote(4) == "4 other reminders speak \(language.title).")
        }
    }

    // MARK: Plural categories

    @Test func everyPluralCategoryIsReachable() throws {
        let en = try #require(bundle("en"))
        for category in PluralLabel.Category.allCases {
            let token = "\(category.rawValue) 7"
            #expect(PluralLabel.category(token: token, count: 7) == category)
        }
        // Zero and two keep their own keys instead of collapsing into other.
        let missing = "\u{1}missing"
        for base in ["day streak", "best streak", "days to go"] {
            for category in ["zero", "two", "few", "many"] {
                let key = "\(base) (\(category))"
                #expect(en.localizedString(forKey: key, value: missing, table: nil) != missing, "\(key)")
            }
        }
        #expect(PluralLabel.daysToGo(for: .zero) == "days to go")
        #expect(PluralLabel.daysToGo(for: .two) == "days to go")
        #expect(PluralLabel.dayStreak(for: .two) == "day streak")
        #expect(PluralLabel.bestStreak(for: .zero) == "best streak")
        #expect(PluralLabel.category(token: "garbage", count: 1) == .one)
        #expect(PluralLabel.category(token: "", count: 0) == .other)
    }
}
