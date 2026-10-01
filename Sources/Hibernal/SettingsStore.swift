import AppKit
import Carbon

struct HotKeyBinding: Codable, Equatable {
    var keyCode: UInt16
    var modifierFlags: UInt

    static let `default` = HotKeyBinding(
        keyCode: 42, // \
        modifierFlags: HotKeyFormatter.normalizedModifiers(
            from: NSEvent.ModifierFlags([.control, .option, .command]).rawValue
        ).rawValue
    )
}

final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults = UserDefaults(suiteName: "com.hibernal.settings") ?? .standard

    private enum Keys {
        static let hibernateEnabled = "hibernateEnabled"
        static let restoreAfterWake = "restoreAfterWake"
        static let launchAtLogin = "launchAtLogin"
        static let hotKeyData = "hotKeyData"
        static let keepAwakeOnPowerAdapter = "keepAwakeOnPowerAdapter"
        static let ejectDrivesBeforeHibernate = "ejectDrivesBeforeHibernate"
        static let backgroundServiceActive = "backgroundServiceActive"
        static let allowTermination = "allowTermination"
    }

    func setAllowTermination(_ allowed: Bool) {
        defaults.set(allowed, forKey: Keys.allowTermination)
    }

    func consumeAllowTermination() -> Bool {
        let allowed = defaults.bool(forKey: Keys.allowTermination)
        if allowed {
            defaults.set(false, forKey: Keys.allowTermination)
        }
        return allowed
    }

    var hibernateEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.hibernateEnabled) == nil { return true }
            return defaults.bool(forKey: Keys.hibernateEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.hibernateEnabled) }
    }

    var restoreAfterWake: Bool {
        get {
            if defaults.object(forKey: Keys.restoreAfterWake) == nil { return true }
            return defaults.bool(forKey: Keys.restoreAfterWake)
        }
        set { defaults.set(newValue, forKey: Keys.restoreAfterWake) }
    }

    var launchAtLogin: Bool {
        get {
            if defaults.object(forKey: Keys.launchAtLogin) == nil { return true }
            return defaults.bool(forKey: Keys.launchAtLogin)
        }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    var hotKey: HotKeyBinding {
        get {
            guard let data = defaults.data(forKey: Keys.hotKeyData),
                  let binding = try? JSONDecoder().decode(HotKeyBinding.self, from: data) else {
                return .default
            }
            return binding
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.hotKeyData)
            }
        }
    }

    var keepAwakeOnPowerAdapter: Bool {
        get { defaults.bool(forKey: Keys.keepAwakeOnPowerAdapter) }
        set { defaults.set(newValue, forKey: Keys.keepAwakeOnPowerAdapter) }
    }

    var ejectDrivesBeforeHibernate: Bool {
        get { defaults.bool(forKey: Keys.ejectDrivesBeforeHibernate) }
        set { defaults.set(newValue, forKey: Keys.ejectDrivesBeforeHibernate) }
    }

    var backgroundServiceActive: Bool {
        get {
            if defaults.object(forKey: Keys.backgroundServiceActive) == nil { return true }
            return defaults.bool(forKey: Keys.backgroundServiceActive)
        }
        set { defaults.set(newValue, forKey: Keys.backgroundServiceActive) }
    }

    func hotKeyDisplayString() -> String {
        HotKeyFormatter.displayString(for: hotKey)
    }
}

enum HotKeyFormatter {
    private static let keyNames: [UInt16: String] = [
        49: "Space", 36: "Return", 53: "Escape", 44: "/", 42: "\\",
        4: "H", 0: "A", 1: "S", 2: "D", 3: "F", 5: "G",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
    ]

    static func displayString(for binding: HotKeyBinding) -> String {
        let flags = HotKeyFormatter.normalizedModifiers(from: binding.modifierFlags)
        var parts: [String] = []
        if flags.contains(.control) { parts.append("Control") }
        if flags.contains(.option) { parts.append("Option") }
        if flags.contains(.command) { parts.append("Command") }
        if flags.contains(.shift) { parts.append("Shift") }

        let keyName = keyNames[binding.keyCode] ?? "Key \(binding.keyCode)"
        parts.append(keyName)
        return parts.joined(separator: " + ")
    }

    static func normalizedModifiers(from rawValue: UInt) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: rawValue)
            .intersection(.deviceIndependentFlagsMask)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let normalized = flags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if normalized.contains(.command) { carbon |= UInt32(cmdKey) }
        if normalized.contains(.option) { carbon |= UInt32(optionKey) }
        if normalized.contains(.control) { carbon |= UInt32(controlKey) }
        if normalized.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}