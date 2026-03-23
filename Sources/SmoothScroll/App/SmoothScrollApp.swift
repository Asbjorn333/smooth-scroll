@preconcurrency import AppKit
import Foundation

@main
struct SmoothScrollApp {
    static func main() {
        let options = CLIOptions.parseOrExit()

        if options.headless {
            runHeadless(options: options)
            return
        }

        var settings = SettingsStore.loadSettings()
        settings = options.applyingOverrides(to: settings)
        SettingsStore.saveSettings(settings)

        let enabled = SettingsStore.loadEnabled()
        let windowSwitcherEnabled = SettingsStore.loadWindowSwitcherEnabled()

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = MenuBarController(
            settings: settings,
            enabled: enabled,
            windowSwitcherEnabled: windowSwitcherEnabled
        )
        app.delegate = delegate
        app.run()
    }

    private static func runHeadless(options: CLIOptions) {
        let settings = options.applyingOverrides(to: EngineSettings.default)
        PointerSpeedManager.apply(settings.pointerSpeed)
        let engine = ScrollEngine(settings: settings)

        guard engine.start(promptForPermissions: true) else {
            fputs("Failed to start SmoothScroll. Check Accessibility and Input Monitoring permissions.\n", stderr)
            exit(1)
        }

        engine.setEnabled(true)

        print("SmoothScroll headless mode running. Press Ctrl+C to stop.")
        print(
            "Config: speed=\(settings.speed), smoothness=\(settings.smoothness), decay=\(settings.decay), fps=\(settings.fps), pointerSpeed=\(settings.pointerSpeed)"
        )

        RunLoop.main.run()
    }
}
