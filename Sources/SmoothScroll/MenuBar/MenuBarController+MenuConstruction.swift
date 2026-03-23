@preconcurrency import AppKit

extension MenuBarController {
    func constructMenuBarUI() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = makeStatusBarImage()
            button.imagePosition = .imageOnly
            button.title = ""
            button.toolTip = "SmoothScroll"
        }

        menu.delegate = self
        menu.autoenablesItems = false

        let titleItem = NSMenuItem(title: "SmoothScroll", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEngine(_:)), keyEquivalent: "")
        enabledItem?.target = self
        if let enabledItem { menu.addItem(enabledItem) }

        windowSwitcherItem = NSMenuItem(
            title: "Window Switcher (Cmd+Tab)",
            action: #selector(toggleWindowSwitcher(_:)),
            keyEquivalent: ""
        )
        windowSwitcherItem?.target = self
        if let windowSwitcherItem { menu.addItem(windowSwitcherItem) }

        keyboardCleaningItem = NSMenuItem(
            title: "Enable Keyboard Cleaning",
            action: #selector(toggleKeyboardCleaning(_:)),
            keyEquivalent: ""
        )
        keyboardCleaningItem?.target = self
        if let keyboardCleaningItem { menu.addItem(keyboardCleaningItem) }

        menu.addItem(.separator())

        let mouseButtonsHeader = NSMenuItem(title: "Mouse Buttons", action: nil, keyEquivalent: "")
        mouseButtonsHeader.isEnabled = false
        menu.addItem(mouseButtonsHeader)

        let sideButtonPrimaryItem = makeMouseButtonMappingMenuItem(
            slot: .primary,
            action: settings.sideButtonPrimaryAction,
            keyboardKey: settings.sideButtonPrimaryKeyboardKey
        )
        self.sideButtonPrimaryItem = sideButtonPrimaryItem
        menu.addItem(sideButtonPrimaryItem)

        let sideButtonSecondaryItem = makeMouseButtonMappingMenuItem(
            slot: .secondary,
            action: settings.sideButtonSecondaryAction,
            keyboardKey: settings.sideButtonSecondaryKeyboardKey
        )
        self.sideButtonSecondaryItem = sideButtonSecondaryItem
        menu.addItem(sideButtonSecondaryItem)

        menu.addItem(.separator())

        let speedRow = makeSliderRow(
            title: "Speed",
            value: settings.speed,
            min: TuningLimits.speed.lowerBound,
            max: TuningLimits.speed.upperBound,
            action: #selector(speedChanged(_:))
        )
        speedSlider = speedRow.slider
        speedLabel = speedRow.valueLabel
        menu.addItem(speedRow.item)

        let pointerSpeedRow = makeSliderRow(
            title: "Pointer Speed",
            value: settings.pointerSpeed,
            min: TuningLimits.pointerSpeed.lowerBound,
            max: TuningLimits.pointerSpeed.upperBound,
            action: #selector(pointerSpeedChanged(_:))
        )
        pointerSpeedSlider = pointerSpeedRow.slider
        pointerSpeedLabel = pointerSpeedRow.valueLabel
        menu.addItem(pointerSpeedRow.item)

        let smoothnessRow = makeSliderRow(
            title: "Smoothness",
            value: settings.smoothness,
            min: TuningLimits.smoothness.lowerBound,
            max: TuningLimits.smoothness.upperBound,
            action: #selector(smoothnessChanged(_:))
        )
        smoothnessSlider = smoothnessRow.slider
        smoothnessLabel = smoothnessRow.valueLabel
        menu.addItem(smoothnessRow.item)

        let decayRow = makeSliderRow(
            title: "Decay",
            value: settings.decay,
            min: TuningLimits.decay.lowerBound,
            max: TuningLimits.decay.upperBound,
            action: #selector(decayChanged(_:))
        )
        decaySlider = decayRow.slider
        decayLabel = decayRow.valueLabel
        menu.addItem(decayRow.item)

        let fpsRow = makeSliderRow(
            title: "FPS",
            value: settings.fps,
            min: TuningLimits.fps.lowerBound,
            max: TuningLimits.fps.upperBound,
            action: #selector(fpsChanged(_:))
        )
        fpsSlider = fpsRow.slider
        fpsLabel = fpsRow.valueLabel
        menu.addItem(fpsRow.item)

        menu.addItem(.separator())

        saveSettingsItem = NSMenuItem(title: "Save Settings", action: #selector(saveSettingsNow(_:)), keyEquivalent: "s")
        saveSettingsItem?.target = self
        if let saveSettingsItem { menu.addItem(saveSettingsItem) }

        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchAtLoginItem?.target = self
        if let launchAtLoginItem { menu.addItem(launchAtLoginItem) }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func makeStatusBarImage() -> NSImage {
        let symbolCandidates = [
            "arrow.up.and.down",
            "arrow.up.and.down.circle",
            "line.3.horizontal.decrease.circle"
        ]

        for symbolName in symbolCandidates {
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "SmoothScroll") {
                let configured = image.withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) ?? image
                configured.isTemplate = true
                return configured
            }
        }

        let fallback = NSImage(size: NSSize(width: 16, height: 16))
        fallback.lockFocus()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let text = "↕" as NSString
        let textSize = text.size(withAttributes: attributes)
        let origin = NSPoint(x: (16 - textSize.width) / 2, y: (16 - textSize.height) / 2)
        text.draw(at: origin, withAttributes: attributes)
        fallback.unlockFocus()
        fallback.isTemplate = true
        return fallback
    }

    private func makeSliderRow(
        title: String,
        value: Double,
        min: Double,
        max: Double,
        action: Selector
    ) -> (item: NSMenuItem, slider: NSSlider, valueLabel: NSTextField) {
        let rowWidth: CGFloat = 270
        let rowHeight: CGFloat = 48
        let container = NSView(frame: NSRect(x: 0, y: 0, width: rowWidth, height: rowHeight))

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.frame = NSRect(x: 12, y: 30, width: 140, height: 14)

        let valueLabel = NSTextField(labelWithString: "")
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: rowWidth - 90, y: 30, width: 78, height: 14)

        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: action)
        slider.isContinuous = true
        slider.controlSize = .small
        slider.frame = NSRect(x: 12, y: 8, width: rowWidth - 24, height: 20)

        container.addSubview(label)
        container.addSubview(valueLabel)
        container.addSubview(slider)

        let item = NSMenuItem()
        item.view = container
        return (item, slider, valueLabel)
    }

    private func makeMouseButtonMappingMenuItem(
        slot: SideMouseButtonSlot,
        action: MouseButtonAction,
        keyboardKey: MouseButtonKeyboardKey
    ) -> NSMenuItem {
        let item = NSMenuItem(title: slot.title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: slot.title)
        submenu.autoenablesItems = false

        for mapping in MouseButtonAction.directCases {
            let mappingItem = NSMenuItem(
                title: mapping.title,
                action: #selector(sideButtonActionChanged(_:)),
                keyEquivalent: ""
            )
            mappingItem.target = self
            mappingItem.tag = slot.rawValue
            mappingItem.representedObject = "action:\(mapping.rawValue)"
            mappingItem.state = mapping == action ? .on : .off
            submenu.addItem(mappingItem)
        }

        submenu.addItem(.separator())

        let keyboardKeyItem = NSMenuItem(title: "Keyboard Key", action: nil, keyEquivalent: "")
        let keyboardKeyMenu = NSMenu(title: "Keyboard Key")
        keyboardKeyMenu.autoenablesItems = false
        for key in MouseButtonKeyboardKey.allCases {
            let keyItem = NSMenuItem(
                title: key.title,
                action: #selector(sideButtonActionChanged(_:)),
                keyEquivalent: ""
            )
            keyItem.target = self
            keyItem.tag = slot.rawValue
            keyItem.representedObject = "key:\(key.rawValue)"
            keyItem.state = action == .keyboardKey && key == keyboardKey ? .on : .off
            keyboardKeyMenu.addItem(keyItem)
        }
        keyboardKeyItem.submenu = keyboardKeyMenu
        keyboardKeyItem.state = action == .keyboardKey ? .on : .off
        submenu.addItem(keyboardKeyItem)

        item.submenu = submenu
        return item
    }
}
