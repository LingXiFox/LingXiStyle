import Foundation

/// The language choices exposed in Settings. The selected value is stored separately from
/// AppleLanguages so the current choice can be shown before the app is relaunched.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"

    static let preferenceKey = "LingXiStyle.appLanguage"
    private static let appleLanguagesKey = "AppleLanguages"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .system:
            return String(localized: "settings.language.system", defaultValue: "跟随系统")
        case .simplifiedChinese:
            return "简体中文"
        case .traditionalChinese:
            return "繁體中文"
        case .english:
            return "English"
        case .japanese:
            return "日本語"
        }
    }

    static var current: AppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: preferenceKey),
              let language = AppLanguage(rawValue: raw) else {
            return .system
        }
        return language
    }

    /// Applies the choice to the app's own preferences. Bundle localization is resolved at
    /// launch, so the UI asks the user to reopen the app after changing this value.
    static func apply(_ language: AppLanguage) {
        let defaults = UserDefaults.standard
        if language == .system {
            defaults.removeObject(forKey: appleLanguagesKey)
        } else {
            defaults.set([language.rawValue], forKey: appleLanguagesKey)
        }
        defaults.set(language.rawValue, forKey: preferenceKey)
    }
}
