@preconcurrency import AppKit
import Foundation

extension MenuBarController {
    @objc func toggleEngine(_ sender: NSMenuItem) {
        engineEnabled.toggle()
        SettingsStore.saveEnabled(engineEnabled)
        applyEngineEnabledState(promptForPermissions: true)
        updateMenuState()
    }

    @objc func toggleWindowSwitcher(_ sender: NSMenuItem) {
        windowSwitcherEnabled.toggle()
        SettingsStore.saveWindowSwitcherEnabled(windowSwitcherEnabled)
        applyWindowSwitcherEnabledState(promptForPermissions: true)
        updateMenuState()
    }

    @objc func toggleKeyboardCleaning(_ sender: NSMenuItem) {
        if keyboardCleaningEnabled {
            disableKeyboardCleaning(showTimeoutAlert: false)
            return
        }

        guard keyboardCleaningManager.start(promptForPermissions: true) else {
            showAlert(
                title: "Permissions Required",
                message: "Enable Accessibility and Input Monitoring for SmoothScroll in System Settings > Privacy & Security."
            )
            keyboardCleaningEnabled = false
            updateMenuState()
            return
        }

        keyboardCleaningEnabled = true
        scheduleKeyboardCleaningAutoDisable()
        updateMenuState()
    }

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let shouldEnable = sender.state != .on
        if shouldEnable {
            let executablePath = resolveExecutablePath()
            let success = launchAgentManager.enable(executablePath: executablePath)
            if !success {
                showAlert(
                    title: "Launch at Login Failed",
                    message: "Could not install launch agent. Try running from a built binary instead of a temporary path."
                )
            }
        } else {
            _ = launchAgentManager.disable()
        }

        launchAtLoginItem?.state = launchAgentManager.isEnabled() ? .on : .off
    }

    @objc func speedChanged(_ sender: NSSlider) {
        settings.speed = sender.doubleValue.rounded()
        sender.doubleValue = settings.speed
        saveAndApplySettings()
    }

    @objc func smoothnessChanged(_ sender: NSSlider) {
        settings.smoothness = (sender.doubleValue * 100).rounded() / 100
        sender.doubleValue = settings.smoothness
        saveAndApplySettings()
    }

    @objc func pointerSpeedChanged(_ sender: NSSlider) {
        settings.pointerSpeed = (sender.doubleValue * 10).rounded() / 10
        sender.doubleValue = settings.pointerSpeed
        saveAndApplySettings()
    }

    @objc func decayChanged(_ sender: NSSlider) {
        settings.decay = (sender.doubleValue * 10).rounded() / 10
        sender.doubleValue = settings.decay
        saveAndApplySettings()
    }

    @objc func fpsChanged(_ sender: NSSlider) {
        settings.fps = (sender.doubleValue / 5).rounded() * 5
        sender.doubleValue = settings.fps
        saveAndApplySettings()
    }

    @objc func sideButtonActionChanged(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? String,
              let slot = SideMouseButtonSlot(rawValue: sender.tag) else {
            return
        }

        if payload.hasPrefix("action:") {
            let rawValue = String(payload.dropFirst("action:".count))
            guard let action = MouseButtonAction(rawValue: rawValue) else {
                return
            }
            setSideButtonAction(action, for: slot)
        } else if payload.hasPrefix("key:") {
            let rawValue = String(payload.dropFirst("key:".count))
            guard let keyboardKey = MouseButtonKeyboardKey(rawValue: rawValue) else {
                return
            }
            setSideButtonKeyboardKey(keyboardKey, for: slot)
            setSideButtonAction(.keyboardKey, for: slot)
        } else {
            return
        }

        saveAndApplySettings()
    }

    @objc func saveSettingsNow(_ sender: NSMenuItem) {
        persistSettings()
        sender.title = "Saved ✓"
        sender.isEnabled = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.saveSettingsItem?.title = "Save Settings"
            self?.saveSettingsItem?.isEnabled = true
        }
    }

    @objc func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
