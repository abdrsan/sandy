import Foundation
import Testing
@testable import Sandy

struct LocalizationTests {
    private let languages = InterfaceLanguage.allCases.filter { $0 != .system }.map(\.rawValue)
    private var resources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources")
    }

    @Test func allLanguagesAreSelectableByMacOS() {
        for language in languages {
            #expect(Bundle.preferredLocalizations(from: languages, forPreferences: [language]).first == language)
        }
    }

    @Test func everyLanguageInSettingsHasResources() throws {
        let folders = try FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "lproj" }.map { $0.deletingPathExtension().lastPathComponent }
        #expect(Set(folders) == Set(languages))
    }

    @Test func bundlesResolveMultilineMessagesAndFormattedValues() throws {
        let multilineKey = "Wipe the keys and the screen. Hold Esc or − for %d s to\nunlock; it also unlocks by itself after a minute"
        for language in languages {
            let bundle = try #require(Bundle(url: resources.appendingPathComponent("\(language).lproj")))
            let message = bundle.localizedString(forKey: multilineKey, value: "MISSING", table: nil)
            #expect(message != "MISSING")
            #expect(message.contains("\n"))
            let formatted = String(format: message, 3)
            #expect(formatted.contains("3"))
            #expect(!formatted.contains("%d"))
            let tokens = bundle.localizedString(forKey: "Tokens · in %@ · out %@", value: "MISSING", table: nil)
            let counts = String(format: tokens, "123", "456")
            #expect(counts.contains("123"))
            #expect(counts.contains("456"))
            let permission = bundle.localizedString(forKey: "NSCalendarsFullAccessUsageDescription", value: "MISSING", table: "InfoPlist")
            #expect(permission != "MISSING")
        }
    }
}
