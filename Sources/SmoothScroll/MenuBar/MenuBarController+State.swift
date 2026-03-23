@preconcurrency import AppKit
import Foundation

extension MenuBarController {
    func applyEngineEnabledState(promptForPermissions: Bool) {
        if engineEnabled {
            if !engine.isRunning() {
                let started = engine.start(promptForPermissions: promptForPermissions)
                if !started {
                    engineEnabled = false
                    SettingsStore.saveEnabled(false)
                    showAlert(
                        title: "Permissions Required",
                        message: "Enable Accessibility and Input Monitoring for SmoothScroll in System Settings > Privacy & Security."
                    )
                    return
                }
            }

            engine.updateSettings(settings)
            engine.setEnabled(true)
        } else {
            engine.setEnabled(false)
        }
    }

    func applyWindowSwitcherEnabledState(promptForPermissions: Bool) {
        if windowSwitcherEnabled {
            if !windowSwitcherManager.isRunning() {
                let started = windowSwitcherManager.start(promptForPermissions: promptForPermissions)
                if !started {
                    windowSwitcherEnabled = false
                    SettingsStore.saveWindowSwitcherEnabled(false)
                    showAlert(
                        title: "Permissions Required",
                        message: "Enable Accessibility and Input Monitoring for SmoothScroll in System Settings > Privacy & Security."
                    )
                    return
                }
            }
        } else {
            windowSwitcherManager.stop()
        }
    }

    func toggleEngineFromMouseButton() {
        engineEnabled.toggle()
        SettingsStore.saveEnabled(engineEnabled)
        applyEngineEnabledState(promptForPermissions: false)
        updateMenuState()
    }

    func saveAndApplySettings() {
        settings = settings.clamped
        persistSettings()
        applySystemPointerSpeed()
        engine.updateSettings(settings)
        updateMenuState()
    }

    func applySystemPointerSpeed() {
        PointerSpeedManager.apply(settings.pointerSpeed)
    }

    func persistSettings() {
        settings = settings.clamped
        SettingsStore.saveSettings(settings)
        SettingsStore.saveEnabled(engineEnabled)
        SettingsStore.saveWindowSwitcherEnabled(windowSwitcherEnabled)
    }

    func setSideButtonAction(_ action: MouseButtonAction, for slot: SideMouseButtonSlot) {
        switch slot {
        case .primary:
            settings.sideButtonPrimaryAction = action
        case .secondary:
            settings.sideButtonSecondaryAction = action
        }
    }

    func setSideButtonKeyboardKey(_ key: MouseButtonKeyboardKey, for slot: SideMouseButtonSlot) {
        switch slot {
        case .primary:
            settings.sideButtonPrimaryKeyboardKey = key
        case .secondary:
            settings.sideButtonSecondaryKeyboardKey = key
        }
    }

    func updateMouseButtonMenuStates() {
        updateMouseButtonMenuState(
            sideButtonPrimaryItem?.submenu,
            selectedAction: settings.sideButtonPrimaryAction,
            selectedKeyboardKey: settings.sideButtonPrimaryKeyboardKey
        )
        updateMouseButtonMenuState(
            sideButtonSecondaryItem?.submenu,
            selectedAction: settings.sideButtonSecondaryAction,
            selectedKeyboardKey: settings.sideButtonSecondaryKeyboardKey
        )
    }

    func updateMouseButtonMenuState(
        _ submenu: NSMenu?,
        selectedAction: MouseButtonAction,
        selectedKeyboardKey: MouseButtonKeyboardKey
    ) {
        guard let submenu else {
            return
        }

        for item in submenu.items {
            if let payload = item.representedObject as? String,
               payload.hasPrefix("action:") {
                let rawValue = String(payload.dropFirst("action:".count))
                let isSelected = rawValue == selectedAction.rawValue
                item.state = isSelected ? .on : .off
            }

            if let keySubmenu = item.submenu {
                item.state = selectedAction == .keyboardKey ? .on : .off
                for keyItem in keySubmenu.items {
                    guard let payload = keyItem.representedObject as? String,
                          payload.hasPrefix("key:") else {
                        continue
                    }

                    let rawValue = String(payload.dropFirst("key:".count))
                    let isSelected = selectedAction == .keyboardKey &&
                        rawValue == selectedKeyboardKey.rawValue
                    keyItem.state = isSelected ? .on : .off
                }
            }
        }
    }

    func scheduleKeyboardCleaningAutoDisable() {
        keyboardCleaningAutoDisableWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.disableKeyboardCleaning(showTimeoutAlert: true)
        }
        keyboardCleaningAutoDisableWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.keyboardCleaningAutoDisableSeconds,
            execute: workItem
        )
    }

    func disableKeyboardCleaning(showTimeoutAlert: Bool) {
        keyboardCleaningAutoDisableWorkItem?.cancel()
        keyboardCleaningAutoDisableWorkItem = nil

        guard keyboardCleaningEnabled else {
            keyboardCleaningManager.stop()
            return
        }

        keyboardCleaningEnabled = false
        keyboardCleaningManager.stop()
        updateMenuState()

        if showTimeoutAlert {
            showAlert(
                title: "Keyboard Cleaning Ended",
                message: "Keyboard input was automatically re-enabled after 2 minutes."
            )
        }
    }

    func updateMenuState() {
        enabledItem?.state = engineEnabled ? .on : .off
        windowSwitcherItem?.state = windowSwitcherEnabled ? .on : .off
        keyboardCleaningItem?.state = keyboardCleaningEnabled ? .on : .off
        keyboardCleaningItem?.title = keyboardCleaningEnabled ? "Disable Keyboard Cleaning" : "Enable Keyboard Cleaning"

        speedSlider?.doubleValue = settings.speed
        pointerSpeedSlider?.doubleValue = settings.pointerSpeed
        smoothnessSlider?.doubleValue = settings.smoothness
        decaySlider?.doubleValue = settings.decay
        fpsSlider?.doubleValue = settings.fps
        updateMouseButtonMenuStates()

        speedLabel?.stringValue = String(format: "%.0f", settings.speed)
        pointerSpeedLabel?.stringValue = String(format: "%.1f", settings.pointerSpeed)
        smoothnessLabel?.stringValue = String(format: "%.2f", settings.smoothness)
        decayLabel?.stringValue = String(format: "%.1f", settings.decay)
        fpsLabel?.stringValue = String(format: "%.0f", settings.fps)

        launchAtLoginItem?.state = launchAgentManager.isEnabled() ? .on : .off
    }

    func resolveExecutablePath() -> String {
        let rawPath = CommandLine.arguments[0]
        if rawPath.hasPrefix("/") {
            return URL(fileURLWithPath: rawPath).standardizedFileURL.path
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return URL(fileURLWithPath: rawPath, relativeTo: cwd).standardizedFileURL.path
    }

    func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }
}
