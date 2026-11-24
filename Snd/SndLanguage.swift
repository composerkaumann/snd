import Foundation

enum SndLanguage: String, CaseIterable {
    case system
    case english = "en"
    case estonian = "et"

    private static let preferenceKey = "SndLanguage"

    static var preference: SndLanguage {
        get {
            let stored = UserDefaults.standard.string(forKey: preferenceKey) ?? ""
            return SndLanguage(rawValue: stored) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: preferenceKey)
        }
    }

    var menuTitle: String {
        switch self {
        case .system: Self.text("System Default")
        case .english: "English"
        case .estonian: "Eesti"
        }
    }

    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let mainBundle = Bundle.main
        let language = preference
        let bundle: Bundle
        if language != .system,
           let url = mainBundle.url(forResource: language.rawValue, withExtension: "lproj"),
           let localizedBundle = Bundle(url: url) {
            bundle = localizedBundle
        } else {
            bundle = mainBundle
        }
        let value = bundle.localizedString(forKey: key, value: key, table: nil)
        return arguments.isEmpty ? value : String(format: value, arguments: arguments)
    }

    static func outputConfirmation(for name: String, changed: Bool) -> String {
        changed ? text("%@ is now the active sound output.", name)
                : text("%@ is already the active sound output.", name)
    }
}
