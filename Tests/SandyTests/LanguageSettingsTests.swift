import Foundation
import Testing
@testable import Sandy

@MainActor
struct LanguageSettingsTests {
    @Test(arguments: InterfaceLanguage.allCases.filter { $0 != .system })
    func everyLanguageCanBeSelectedAndRestored(_ language: InterfaceLanguage) throws {
        let name = "SandyTests.Language.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = LanguageSettings(defaults: defaults)
        store.select(language)
        #expect(AppLocalization.language(defaults: defaults) == language.rawValue)
        #expect(LanguageSettings(defaults: defaults).selection == language)
    }

    @Test func languageChoicePersistsAndSystemOptionRemovesOverride() throws {
        let name = "SandyTests.Language.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = LanguageSettings(defaults: defaults)
        #expect(store.selection == .system)
        store.select(.chinese)
        #expect(AppLocalization.language(defaults: defaults) == "zh-Hans")
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["zh-Hans"])
        #expect(LanguageSettings(defaults: defaults).selection == .chinese)
        store.select(.fr)
        #expect(store.locale.language.languageCode?.identifier == "fr")
        store.select(.system)
        #expect(defaults.persistentDomain(forName: name)?["AppleLanguages"] == nil)
        #expect(LanguageSettings(defaults: defaults).selection == .system)
    }

    @Test func unknownSavedLanguageFallsBackToSupportedSystemLanguage() throws {
        let name = "SandyTests.Language.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("unknown", forKey: InterfaceLanguage.preferenceKey)
        defaults.set(["fr-CA", "en"], forKey: "AppleLanguages")
        #expect(LanguageSettings(defaults: defaults).selection == .system)
        #expect(AppLocalization.language(defaults: defaults) == "fr")
    }
}
