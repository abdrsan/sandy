import Foundation
import Combine

enum InterfaceLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, en, ru, kk, de, fr, es, ja
    case chinese = "zh-Hans"

    static let preferenceKey = "SandyInterfaceLanguage"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: localized("System Language")
        case .en: "English"
        case .ru: "Русский"
        case .kk: "Қазақша"
        case .de: "Deutsch"
        case .fr: "Français"
        case .es: "Español"
        case .chinese: "简体中文"
        case .ja: "日本語"
        }
    }
}

enum AppLocalization {
    private static let bundles: [String: Bundle] = Dictionary(uniqueKeysWithValues:
        InterfaceLanguage.allCases.filter { $0 != .system }.compactMap { language in
            guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { return nil }
            return (language.rawValue, bundle)
        })

    static var language: String { language(defaults: .standard) }

    static func language(defaults: UserDefaults) -> String {
        if let raw = defaults.string(forKey: InterfaceLanguage.preferenceKey),
           let choice = InterfaceLanguage(rawValue: raw), choice != .system {
            return choice.rawValue
        }
        let supported = InterfaceLanguage.allCases.filter { $0 != .system }.map(\.rawValue)
        let preferred = defaults.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
        return Bundle.preferredLocalizations(from: supported, forPreferences: preferred).first ?? "en"
    }

    static var bundle: Bundle { bundles[language] ?? .main }
}

@MainActor
final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()
    private let defaults: UserDefaults
    @Published private(set) var selection: InterfaceLanguage
    var locale: Locale { Locale(identifier: AppLocalization.language(defaults: defaults)) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = defaults.string(forKey: InterfaceLanguage.preferenceKey)
            .flatMap(InterfaceLanguage.init(rawValue:)) ?? .system
    }

    func select(_ language: InterfaceLanguage) {
        guard language != selection else { return }
        defaults.set(language.rawValue, forKey: InterfaceLanguage.preferenceKey)
        // Native permission dialogs use this preference on the next launch.
        // The panel itself switches immediately through AppLocalization.
        if language == .system {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([language.rawValue], forKey: "AppleLanguages")
        }
        selection = language
    }
}
