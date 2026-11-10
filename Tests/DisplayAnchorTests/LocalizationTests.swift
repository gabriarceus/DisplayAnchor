import Foundation
import MenuBarKit
import Testing

@testable import DisplayAnchor

struct LocalizationTests {
    /// A missing key silently shows English; a mismatched specifier shows the raw
    /// format string (the localizer refuses to format it).
    @Test func everyLanguageHasTheEnglishKeysAndFormatSpecifiers() throws {
        let english = try table("en")
        let languages = Bundle.appResources.localizations.filter { $0 != "en" && $0 != "Base" }
        #expect(!languages.isEmpty)

        for language in languages {
            let translated = try table(language)
            #expect(Set(translated.keys) == Set(english.keys), "\(language)")
            for (key, value) in english {
                #expect(specifiers(translated[key] ?? "") == specifiers(value), "\(language): \(key)")
            }
        }
    }

    private func table(_ language: String) throws -> [String: String] {
        let url = try #require(
            Bundle.appResources.url(
                forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language))
        return try #require(NSDictionary(contentsOf: url) as? [String: String])
    }

    /// Conversion characters of the format specifiers, ignoring positional order.
    private func specifiers(_ format: String) -> [Character] {
        format.matches(of: /%(?:\d+\$)?[0-9.]*([@a-zA-Z])/).compactMap { $0.output.1.first }.sorted()
    }
}

struct LocalizedTextTests {
    @Test(arguments: [
        ("en", 1, "1 display"), ("en", 3, "3 displays"), ("it", 1, "1 schermo"), ("it", 3, "3 schermi"),
    ])
    func displayCountUsesThePluralKeyOfEachLanguage(language: String, count: Int, expected: String) {
        let localizer = Localizer(bundle: .appResources, language: language)
        #expect(localizer.displayCount(count) == expected)
    }

    @Test func relativeTextFollowsTheLocale() {
        let hourAgo = Date().addingTimeInterval(-3600)
        #expect(
            hourAgo.relativeText(locale: Locale(identifier: "en"))
                != hourAgo.relativeText(locale: Locale(identifier: "it")))
    }

    @MainActor @Test func systemLanguageSelectionResolvesToPreferredLocalization() throws {
        let suite = "LocalizationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let config = AppConfig(defaults: defaults)
        #expect(config.appLanguage == nil)
        let expected =
            Bundle.preferredLocalizations(
                from: Bundle.appResources.localizations,
                forPreferences: Locale.preferredLanguages
            ).first ?? "en"
        #expect(config.effectiveLanguage == expected)
        #expect(config.l("common_language_system") == (expected == "it" ? "Sistema" : "System"))

        config.appLanguageRaw = "it"
        #expect(config.effectiveLanguage == "it")
        #expect(config.effectiveLocale.language.languageCode?.identifier == "it")
        #expect(config.l("common_language") == "Lingua")

        config.appLanguageRaw = "en"
        #expect(config.effectiveLanguage == "en")
        #expect(config.effectiveLocale.language.languageCode?.identifier == "en")
        #expect(config.l("common_language") == "Language")
    }
}
