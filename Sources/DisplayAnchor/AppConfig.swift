import Foundation
import MenuBarKit

/// Panel appearance: follow the system, or force dark/light.
enum AppAppearance: String, CaseIterable {
    case system
    case dark
    case light
}

/// How the glass tint washed over the panel chrome is chosen.
enum AppTintMode: String, CaseIterable {
    case none
    /// Follow the macOS accent color.
    case system
    /// Fixed color picked from the palette.
    case custom
}

/// Palette for the custom glass tint, mirroring the macOS accent colors.
enum AppTint: String, CaseIterable {
    case blue
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case graphite
    case teal
}

/// User configuration, persisted in UserDefaults with immediate write-through.
@MainActor
final class AppConfig: ObservableObject {
    private enum Keys {
        static let autoRestoreEnabled = "autoRestoreOnReconnect"
        static let notifyOnRestore = "notifyOnRestore"
        static let settleSeconds = "settleSeconds"
        static let appAppearance = "appAppearance"
        static let appTintMode = "appTintMode"
        static let appTint = "appTint"
        static let appLanguage = "appLanguage"
    }

    private let defaults = UserDefaults.standard

    @Published var autoRestoreEnabled: Bool { didSet { defaults.set(autoRestoreEnabled, forKey: Keys.autoRestoreEnabled) } }
    @Published var notifyOnRestore: Bool { didSet { defaults.set(notifyOnRestore, forKey: Keys.notifyOnRestore) } }
    @Published var settleSeconds: Int { didSet { defaults.set(settleSeconds, forKey: Keys.settleSeconds) } }
    /// Raw appearance selection; any value that is not an `AppAppearance` raw value falls back to system.
    @Published var appAppearanceRaw: String { didSet { defaults.set(appAppearanceRaw, forKey: Keys.appAppearance) } }
    /// Raw tint mode selection; any value that is not an `AppTintMode` raw value falls back to none.
    @Published var appTintModeRaw: String { didSet { defaults.set(appTintModeRaw, forKey: Keys.appTintMode) } }
    /// Raw custom tint selection; any value that is not an `AppTint` raw value falls back to orange.
    @Published var appTintRaw: String { didSet { defaults.set(appTintRaw, forKey: Keys.appTint) } }
    /// Raw UI language selection; an empty value follows the system language.
    @Published var appLanguageRaw: String { didSet { defaults.set(appLanguageRaw, forKey: Keys.appLanguage) } }

    var appAppearance: AppAppearance { AppAppearance(rawValue: appAppearanceRaw) ?? .system }

    var appTintMode: AppTintMode { AppTintMode(rawValue: appTintModeRaw) ?? .none }

    var appTint: AppTint { AppTint(rawValue: appTintRaw) ?? .orange }

    /// The forced UI language code, or `nil` to follow the system.
    var appLanguage: String? { appLanguageRaw.isEmpty ? nil : appLanguageRaw }

    /// Localizer resolving strings from this app's bundle in the selected language.
    var localizer: Localizer { Localizer(bundle: .appResources, language: appLanguage) }

    /// The localized value for [key] in the selected language.
    func l(_ key: String, _ arguments: CVarArg...) -> String {
        localizer.string(key, arguments: arguments)
    }

    init() {
        defaults.register(defaults: [
            Keys.autoRestoreEnabled: false,
            Keys.notifyOnRestore: true,
            Keys.settleSeconds: 3,
            Keys.appAppearance: AppAppearance.system.rawValue,
            Keys.appTintMode: AppTintMode.none.rawValue,
            Keys.appTint: AppTint.orange.rawValue,
            Keys.appLanguage: "",
        ])
        // Migrate the pre-mode tint value: "none" was a tint choice, now a mode.
        if defaults.string(forKey: Keys.appTint) == "none" {
            defaults.set(AppTintMode.none.rawValue, forKey: Keys.appTintMode)
            defaults.removeObject(forKey: Keys.appTint)
        }
        autoRestoreEnabled = defaults.bool(forKey: Keys.autoRestoreEnabled)
        notifyOnRestore = defaults.bool(forKey: Keys.notifyOnRestore)
        settleSeconds = defaults.integer(forKey: Keys.settleSeconds)
        appAppearanceRaw = defaults.string(forKey: Keys.appAppearance) ?? AppAppearance.system.rawValue
        appTintModeRaw = defaults.string(forKey: Keys.appTintMode) ?? AppTintMode.none.rawValue
        appTintRaw = defaults.string(forKey: Keys.appTint) ?? AppTint.orange.rawValue
        appLanguageRaw = defaults.string(forKey: Keys.appLanguage) ?? ""
    }
}
