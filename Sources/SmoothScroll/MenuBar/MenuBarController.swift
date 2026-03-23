@preconcurrency import AppKit
import Foundation

@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let keyboardCleaningAutoDisableSeconds: TimeInterval = 120.0

    var settings: EngineSettings
    var engineEnabled: Bool
    var windowSwitcherEnabled: Bool
    var keyboardCleaningEnabled = false

    let engine: ScrollEngine
    let windowSwitcherManager = WindowSwitcherManager()
    let keyboardCleaningManager = KeyboardCleaningManager()
    let launchAgentManager = LaunchAgentManager()

    var statusItem: NSStatusItem?
    let menu = NSMenu()

    var enabledItem: NSMenuItem?
    var windowSwitcherItem: NSMenuItem?
    var keyboardCleaningItem: NSMenuItem?
    var saveSettingsItem: NSMenuItem?
    var launchAtLoginItem: NSMenuItem?
    var keyboardCleaningAutoDisableWorkItem: DispatchWorkItem?

    var speedSlider: NSSlider?
    var pointerSpeedSlider: NSSlider?
    var smoothnessSlider: NSSlider?
    var decaySlider: NSSlider?
    var fpsSlider: NSSlider?
    var sideButtonPrimaryItem: NSMenuItem?
    var sideButtonSecondaryItem: NSMenuItem?

    var speedLabel: NSTextField?
    var pointerSpeedLabel: NSTextField?
    var smoothnessLabel: NSTextField?
    var decayLabel: NSTextField?
    var fpsLabel: NSTextField?

    init(settings: EngineSettings, enabled: Bool, windowSwitcherEnabled: Bool) {
        self.settings = settings.clamped
        self.engineEnabled = enabled
        self.windowSwitcherEnabled = windowSwitcherEnabled
        self.engine = ScrollEngine(settings: settings)
        super.init()
        self.engine.onToggleEnabledRequested = { [weak self] in
            self?.toggleEngineFromMouseButton()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        constructMenuBarUI()
        applySystemPointerSpeed()
        applyEngineEnabledState(promptForPermissions: true)
        applyWindowSwitcherEnabledState(promptForPermissions: true)
        updateMenuState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        disableKeyboardCleaning(showTimeoutAlert: false)
        windowSwitcherManager.stop()
        engine.stop()
    }

    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginItem?.state = launchAgentManager.isEnabled() ? .on : .off
        saveSettingsItem?.title = "Save Settings"
        saveSettingsItem?.isEnabled = true
        updateMenuState()
    }
}
