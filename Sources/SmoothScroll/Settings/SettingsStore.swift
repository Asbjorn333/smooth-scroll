import Foundation

enum SettingsStore {
    private static let keyEnabled = "smoothscroll.enabled"
    private static let keyWindowSwitcherEnabled = "smoothscroll.windowSwitcherEnabled"
    private static let keySpeed = "smoothscroll.speed"
    private static let keySmoothness = "smoothscroll.smoothness"
    private static let keyDecay = "smoothscroll.decay"
    private static let keyFPS = "smoothscroll.fps"
    private static let keyPointerSpeed = "smoothscroll.pointerSpeed"
    private static let keySideButtonPrimaryAction = "smoothscroll.sideButtonPrimaryAction"
    private static let keySideButtonSecondaryAction = "smoothscroll.sideButtonSecondaryAction"
    private static let keySideButtonPrimaryKeyboardKey = "smoothscroll.sideButtonPrimaryKeyboardKey"
    private static let keySideButtonSecondaryKeyboardKey = "smoothscroll.sideButtonSecondaryKeyboardKey"
    private static let keyDefaultsVersion = "smoothscroll.defaultsVersion"
    private static let currentDefaultsVersion = 5

    static func loadSettings() -> EngineSettings {
        let defaults = UserDefaults.standard
        migrateDefaultsIfNeeded(defaults)

        let speed = defaults.object(forKey: keySpeed) as? Double ?? EngineSettings.default.speed
        let smoothness = defaults.object(forKey: keySmoothness) as? Double ?? EngineSettings.default.smoothness
        let decay = defaults.object(forKey: keyDecay) as? Double ?? EngineSettings.default.decay
        let fps = defaults.object(forKey: keyFPS) as? Double ?? EngineSettings.default.fps
        let pointerSpeed = defaults.object(forKey: keyPointerSpeed) as? Double ?? PointerSpeedManager.currentSystemValue()
        let sideButtonPrimaryAction = MouseButtonAction(
            rawValue: defaults.string(forKey: keySideButtonPrimaryAction) ?? ""
        ) ?? EngineSettings.default.sideButtonPrimaryAction
        let sideButtonSecondaryAction = MouseButtonAction(
            rawValue: defaults.string(forKey: keySideButtonSecondaryAction) ?? ""
        ) ?? EngineSettings.default.sideButtonSecondaryAction
        let sideButtonPrimaryKeyboardKey = MouseButtonKeyboardKey(
            rawValue: defaults.string(forKey: keySideButtonPrimaryKeyboardKey) ?? ""
        ) ?? EngineSettings.default.sideButtonPrimaryKeyboardKey
        let sideButtonSecondaryKeyboardKey = MouseButtonKeyboardKey(
            rawValue: defaults.string(forKey: keySideButtonSecondaryKeyboardKey) ?? ""
        ) ?? EngineSettings.default.sideButtonSecondaryKeyboardKey

        return EngineSettings(
            speed: speed,
            smoothness: smoothness,
            decay: decay,
            fps: fps,
            pointerSpeed: pointerSpeed,
            sideButtonPrimaryAction: sideButtonPrimaryAction,
            sideButtonSecondaryAction: sideButtonSecondaryAction,
            sideButtonPrimaryKeyboardKey: sideButtonPrimaryKeyboardKey,
            sideButtonSecondaryKeyboardKey: sideButtonSecondaryKeyboardKey
        ).clamped
    }

    static func saveSettings(_ settings: EngineSettings) {
        let defaults = UserDefaults.standard
        let clamped = settings.clamped
        defaults.set(clamped.speed, forKey: keySpeed)
        defaults.set(clamped.smoothness, forKey: keySmoothness)
        defaults.set(clamped.decay, forKey: keyDecay)
        defaults.set(clamped.fps, forKey: keyFPS)
        defaults.set(clamped.pointerSpeed, forKey: keyPointerSpeed)
        defaults.set(clamped.sideButtonPrimaryAction.rawValue, forKey: keySideButtonPrimaryAction)
        defaults.set(clamped.sideButtonSecondaryAction.rawValue, forKey: keySideButtonSecondaryAction)
        defaults.set(clamped.sideButtonPrimaryKeyboardKey.rawValue, forKey: keySideButtonPrimaryKeyboardKey)
        defaults.set(clamped.sideButtonSecondaryKeyboardKey.rawValue, forKey: keySideButtonSecondaryKeyboardKey)
    }

    static func loadEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: keyEnabled) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: keyEnabled)
    }

    static func saveEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: keyEnabled)
    }

    static func loadWindowSwitcherEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: keyWindowSwitcherEnabled) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: keyWindowSwitcherEnabled)
    }

    static func saveWindowSwitcherEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: keyWindowSwitcherEnabled)
    }

    private static func migrateDefaultsIfNeeded(_ defaults: UserDefaults) {
        let version = defaults.integer(forKey: keyDefaultsVersion)
        guard version < currentDefaultsVersion else {
            return
        }

        let hadAnySavedValues = defaults.object(forKey: keySpeed) != nil ||
            defaults.object(forKey: keySmoothness) != nil ||
            defaults.object(forKey: keyDecay) != nil ||
            defaults.object(forKey: keyFPS) != nil ||
            defaults.object(forKey: keyPointerSpeed) != nil ||
            defaults.object(forKey: keySideButtonPrimaryAction) != nil ||
            defaults.object(forKey: keySideButtonSecondaryAction) != nil ||
            defaults.object(forKey: keySideButtonPrimaryKeyboardKey) != nil ||
            defaults.object(forKey: keySideButtonSecondaryKeyboardKey) != nil

        if !hadAnySavedValues || hasLegacyDefaultValues(defaults) {
            defaults.set(EngineSettings.default.speed, forKey: keySpeed)
            defaults.set(EngineSettings.default.smoothness, forKey: keySmoothness)
            defaults.set(EngineSettings.default.decay, forKey: keyDecay)
            defaults.set(EngineSettings.default.fps, forKey: keyFPS)
            defaults.set(EngineSettings.default.pointerSpeed, forKey: keyPointerSpeed)
            defaults.set(EngineSettings.default.sideButtonPrimaryAction.rawValue, forKey: keySideButtonPrimaryAction)
            defaults.set(EngineSettings.default.sideButtonSecondaryAction.rawValue, forKey: keySideButtonSecondaryAction)
            defaults.set(EngineSettings.default.sideButtonPrimaryKeyboardKey.rawValue, forKey: keySideButtonPrimaryKeyboardKey)
            defaults.set(EngineSettings.default.sideButtonSecondaryKeyboardKey.rawValue, forKey: keySideButtonSecondaryKeyboardKey)
        }

        defaults.set(currentDefaultsVersion, forKey: keyDefaultsVersion)
    }

    private static func hasLegacyDefaultValues(_ defaults: UserDefaults) -> Bool {
        let legacy = EngineSettings(
            speed: 42.0,
            smoothness: 0.75,
            decay: 12.0,
            fps: 120.0,
            pointerSpeed: PointerSpeedManager.currentSystemValue(),
            sideButtonPrimaryAction: .back,
            sideButtonSecondaryAction: .forward,
            sideButtonPrimaryKeyboardKey: .enter,
            sideButtonSecondaryKeyboardKey: .enter
        )

        let speed = defaults.object(forKey: keySpeed) as? Double ?? legacy.speed
        let smoothness = defaults.object(forKey: keySmoothness) as? Double ?? legacy.smoothness
        let decay = defaults.object(forKey: keyDecay) as? Double ?? legacy.decay
        let fps = defaults.object(forKey: keyFPS) as? Double ?? legacy.fps

        return nearlyEqual(speed, legacy.speed) &&
            nearlyEqual(smoothness, legacy.smoothness) &&
            nearlyEqual(decay, legacy.decay) &&
            nearlyEqual(fps, legacy.fps)
    }

    private static func nearlyEqual(_ a: Double, _ b: Double, epsilon: Double = 0.0001) -> Bool {
        abs(a - b) < epsilon
    }
}
