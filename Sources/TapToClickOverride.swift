import Foundation

// A missing preference must remain missing when the override is restored.
enum TapSetting: String {
    case missing, enabled, disabled

    static func decode(_ value: Any?) -> TapSetting? {
        guard let value else { return .missing }
        guard let number = value as? NSNumber,
              number == 0 || number == 1 else { return nil }
        return number.boolValue ? .enabled : .disabled
    }

    static func cached(current: Any?, legacy: Any?) -> TapSetting? {
        if let current { return (current as? String).flatMap(TapSetting.init(rawValue:)) }
        guard legacy != nil else { return nil }
        return decode(legacy)
    }
}

@MainActor
enum TapToClickOverride {
    private static let domain = "com.apple.AppleMultitouchTrackpad" as CFString
    private static let key = "Clicking" as CFString
    private static let cacheKey = "originalTapToClickState"
    private static let legacyKey = "originalTapToClick"

    private static func read() -> TapSetting? {
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { return nil }
        return TapSetting.decode(CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost))
    }

    private static func write(_ setting: TapSetting) -> Bool {
        let value: CFPropertyList? = setting == .missing ? nil : NSNumber(value: setting == .enabled)
        CFPreferencesSetValue(key, value, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) && read() == setting
    }

    private static func cached() -> TapSetting? {
        let defaults = UserDefaults.standard
        let setting = TapSetting.cached(current: defaults.object(forKey: cacheKey), legacy: defaults.object(forKey: legacyKey))
        if let setting, defaults.object(forKey: cacheKey) == nil {
            defaults.set(setting.rawValue, forKey: cacheKey)
            defaults.removeObject(forKey: legacyKey)
        }
        return setting
    }

    static func disable() -> Bool {
        let defaults = UserDefaults.standard
        if cached() != nil { return write(.disabled) }
        // Keep a readable restoration snapshot before changing the system preference.
        guard defaults.object(forKey: cacheKey) == nil,
              defaults.object(forKey: legacyKey) == nil,
              let original = read() else { return false }
        defaults.set(original.rawValue, forKey: cacheKey)
        return write(.disabled)
    }

    static func restore() -> Bool {
        let defaults = UserDefaults.standard
        guard let original = cached() else {
            return defaults.object(forKey: cacheKey) == nil && defaults.object(forKey: legacyKey) == nil
        }
        guard write(original) else { return false }
        defaults.removeObject(forKey: cacheKey)
        defaults.removeObject(forKey: legacyKey)
        return true
    }
}
