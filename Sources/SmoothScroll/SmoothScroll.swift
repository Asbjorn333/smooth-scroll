@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import CoreGraphics
import Foundation
import IOKit
import IOKit.hidsystem

enum TuningLimits {
    static let speed: ClosedRange<Double> = 1.0...1000.0
    static let smoothness: ClosedRange<Double> = 0.0...0.995
    static let decay: ClosedRange<Double> = 0.1...120.0
    static let fps: ClosedRange<Double> = 30.0...360.0
    static let pointerSpeed: ClosedRange<Double> = 0.0...20.0
}

private func clampValue(_ value: Double, to range: ClosedRange<Double>) -> Double {
    max(range.lowerBound, min(value, range.upperBound))
}

private func aspectFitSize(_ size: NSSize, within maxSize: NSSize) -> NSSize {
    guard size.width > 0, size.height > 0 else {
        return maxSize
    }

    let widthScale = maxSize.width / size.width
    let heightScale = maxSize.height / size.height
    let scale = min(widthScale, heightScale, 1.0)

    return NSSize(
        width: max(1, floor(size.width * scale)),
        height: max(1, floor(size.height * scale))
    )
}

enum MouseButtonAction: String, CaseIterable {
    case passthrough
    case back
    case forward
    case toggleSmoothScroll
    case keyboardKey

    static let directCases: [MouseButtonAction] = [
        .passthrough,
        .back,
        .forward,
        .toggleSmoothScroll
    ]

    var title: String {
        switch self {
        case .passthrough:
            return "Passthrough"
        case .back:
            return "Back (Cmd+[)"
        case .forward:
            return "Forward (Cmd+])"
        case .toggleSmoothScroll:
            return "Toggle SmoothScroll"
        case .keyboardKey:
            return "Keyboard Key"
        }
    }
}

enum SideMouseButton {
    static let primary: Int64 = 3 // Often exposed as "Button 4" by gaming mice.
    static let secondary: Int64 = 4 // Often exposed as "Button 5" by gaming mice.
}

enum SideMouseButtonSlot: Int {
    case primary = 1
    case secondary = 2

    var title: String {
        switch self {
        case .primary:
            return "Side Button 1 (Button 4)"
        case .secondary:
            return "Side Button 2 (Button 5)"
        }
    }
}

enum MouseButtonKeyboardKey: String, CaseIterable {
    case enter
    case tab
    case space
    case escape
    case deleteBackward
    case deleteForward
    case upArrow
    case downArrow
    case leftArrow
    case rightArrow
    case home
    case end
    case pageUp
    case pageDown

    var title: String {
        switch self {
        case .enter:
            return "Enter"
        case .tab:
            return "Tab"
        case .space:
            return "Space"
        case .escape:
            return "Escape"
        case .deleteBackward:
            return "Delete"
        case .deleteForward:
            return "Forward Delete"
        case .upArrow:
            return "Arrow Up"
        case .downArrow:
            return "Arrow Down"
        case .leftArrow:
            return "Arrow Left"
        case .rightArrow:
            return "Arrow Right"
        case .home:
            return "Home"
        case .end:
            return "End"
        case .pageUp:
            return "Page Up"
        case .pageDown:
            return "Page Down"
        }
    }

    var keyCode: CGKeyCode {
        switch self {
        case .enter:
            return 36
        case .tab:
            return 48
        case .space:
            return 49
        case .escape:
            return 53
        case .deleteBackward:
            return 51
        case .deleteForward:
            return 117
        case .upArrow:
            return 126
        case .downArrow:
            return 125
        case .leftArrow:
            return 123
        case .rightArrow:
            return 124
        case .home:
            return 115
        case .end:
            return 119
        case .pageUp:
            return 116
        case .pageDown:
            return 121
        }
    }

    var flags: CGEventFlags {
        []
    }
}

enum KeyboardKeyCode {
    static let tab: CGKeyCode = 48
    static let escape: CGKeyCode = 53
}

enum PointerSpeedManager {
    private static let mouseKey = "com.apple.mouse.scaling"
    private static let trackpadKey = "com.apple.trackpad.scaling"
    private static let hidAccelerationKeys = [
        "HIDPointerAcceleration",
        "HIDMouseAcceleration",
        "HIDTrackpadAcceleration"
    ]
    private static let fallbackPointerSpeed = 5.0
    private static let systemRange: ClosedRange<Double> = 0.0...20.0

    static func currentSystemValue() -> Double {
        if let systemValue = readRuntimeSystemSpeed() {
            return uiSpeed(fromSystem: systemValue)
        }

        if let systemValue = readCurrentSystemSpeed() {
            return uiSpeed(fromSystem: systemValue)
        }

        return fallbackPointerSpeed
    }

    static func apply(_ pointerSpeed: Double) {
        let uiValue = clampValue(pointerSpeed, to: TuningLimits.pointerSpeed)
        let systemValue = systemSpeed(fromUI: uiValue)
        applyRuntimeSystemSpeed(systemValue)

        for key in [mouseKey, trackpadKey] {
            write(systemValue, key: key, host: kCFPreferencesCurrentHost)
            write(systemValue, key: key, host: kCFPreferencesAnyHost)
        }
    }

    private static func readCurrentSystemSpeed() -> Double? {
        for key in [mouseKey, trackpadKey] {
            if let value = read(key: key, host: kCFPreferencesCurrentHost) {
                return clampValue(value, to: systemRange)
            }

            if let value = read(key: key, host: kCFPreferencesAnyHost) {
                return clampValue(value, to: systemRange)
            }
        }

        return nil
    }

    private static func readRuntimeSystemSpeed() -> Double? {
        withHIDEventStatusHandle { handle in
            for key in hidAccelerationKeys {
                var value = 0.0
                if IOHIDGetAccelerationWithKey(handle, key as CFString, &value) == KERN_SUCCESS {
                    return clampValue(value, to: systemRange)
                }
            }
            return nil
        }
    }

    private static func applyRuntimeSystemSpeed(_ value: Double) {
        _ = withHIDEventStatusHandle { handle in
            for key in hidAccelerationKeys {
                _ = IOHIDSetAccelerationWithKey(handle, key as CFString, value)
            }
            return true
        }
    }

    private static func withHIDEventStatusHandle<T>(_ body: (NXEventHandle) -> T?) -> T? {
        let handle = NXOpenEventStatus()
        guard handle != 0 else {
            return nil
        }
        defer {
            NXCloseEventStatus(handle)
        }
        return body(handle)
    }

    private static func read(key: String, host: CFString) -> Double? {
        guard let value = CFPreferencesCopyValue(
            key as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            host
        ) else {
            return nil
        }

        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if let text = value as? String {
            return Double(text)
        }

        return nil
    }

    private static func write(_ value: Double, key: String, host: CFString) {
        let number = NSNumber(value: value)
        CFPreferencesSetValue(
            key as CFString,
            number,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            host
        )
        _ = CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, host)
    }

    private static func systemSpeed(fromUI uiSpeed: Double) -> Double {
        let uiSpan = TuningLimits.pointerSpeed.upperBound - TuningLimits.pointerSpeed.lowerBound
        guard uiSpan > 0 else {
            return systemRange.lowerBound
        }

        let systemSpan = systemRange.upperBound - systemRange.lowerBound
        let normalized = (uiSpeed - TuningLimits.pointerSpeed.lowerBound) / uiSpan
        return clampValue(systemRange.lowerBound + normalized * systemSpan, to: systemRange)
    }

    private static func uiSpeed(fromSystem systemSpeed: Double) -> Double {
        let systemSpan = systemRange.upperBound - systemRange.lowerBound
        guard systemSpan > 0 else {
            return TuningLimits.pointerSpeed.lowerBound
        }

        let uiSpan = TuningLimits.pointerSpeed.upperBound - TuningLimits.pointerSpeed.lowerBound
        let normalized = (systemSpeed - systemRange.lowerBound) / systemSpan
        return clampValue(TuningLimits.pointerSpeed.lowerBound + normalized * uiSpan, to: TuningLimits.pointerSpeed)
    }
}

struct EngineSettings {
    var speed: Double
    var smoothness: Double
    var decay: Double
    var fps: Double
    var pointerSpeed: Double
    var sideButtonPrimaryAction: MouseButtonAction
    var sideButtonSecondaryAction: MouseButtonAction
    var sideButtonPrimaryKeyboardKey: MouseButtonKeyboardKey
    var sideButtonSecondaryKeyboardKey: MouseButtonKeyboardKey

    static let `default` = EngineSettings(
        speed: 100.0,
        smoothness: 0.80,
        decay: 28.0,
        fps: 120.0,
        pointerSpeed: PointerSpeedManager.currentSystemValue(),
        sideButtonPrimaryAction: .back,
        sideButtonSecondaryAction: .forward,
        sideButtonPrimaryKeyboardKey: .enter,
        sideButtonSecondaryKeyboardKey: .enter
    )

    var clamped: EngineSettings {
        EngineSettings(
            speed: clampValue(speed, to: TuningLimits.speed),
            smoothness: clampValue(smoothness, to: TuningLimits.smoothness),
            decay: clampValue(decay, to: TuningLimits.decay),
            fps: clampValue(fps, to: TuningLimits.fps),
            pointerSpeed: clampValue(pointerSpeed, to: TuningLimits.pointerSpeed),
            sideButtonPrimaryAction: sideButtonPrimaryAction,
            sideButtonSecondaryAction: sideButtonSecondaryAction,
            sideButtonPrimaryKeyboardKey: sideButtonPrimaryKeyboardKey,
            sideButtonSecondaryKeyboardKey: sideButtonSecondaryKeyboardKey
        )
    }

    func mapping(forMouseButtonNumber buttonNumber: Int64) -> (action: MouseButtonAction, keyboardKey: MouseButtonKeyboardKey) {
        switch buttonNumber {
        case SideMouseButton.primary:
            return (sideButtonPrimaryAction, sideButtonPrimaryKeyboardKey)
        case SideMouseButton.secondary:
            return (sideButtonSecondaryAction, sideButtonSecondaryKeyboardKey)
        default:
            return (.passthrough, .enter)
        }
    }
}

struct CLIOptions {
    var headless = false
    var speed: Double?
    var smoothness: Double?
    var decay: Double?
    var fps: Double?
    var pointerSpeed: Double?

    func applyingOverrides(to settings: EngineSettings) -> EngineSettings {
        var updated = settings
        if let speed { updated.speed = speed }
        if let smoothness { updated.smoothness = smoothness }
        if let decay { updated.decay = decay }
        if let fps { updated.fps = fps }
        if let pointerSpeed { updated.pointerSpeed = pointerSpeed }
        return updated.clamped
    }

    static func parseOrExit() -> CLIOptions {
        var options = CLIOptions()
        var index = 1

        while index < CommandLine.arguments.count {
            let arg = CommandLine.arguments[index]
            switch arg {
            case "--headless":
                options.headless = true
            case "--speed":
                options.speed = parseValue(flag: "--speed", index: &index)
            case "--smoothness":
                options.smoothness = parseValue(flag: "--smoothness", index: &index)
            case "--decay":
                options.decay = parseValue(flag: "--decay", index: &index)
            case "--fps":
                options.fps = parseValue(flag: "--fps", index: &index)
            case "--pointer-speed":
                options.pointerSpeed = parseValue(flag: "--pointer-speed", index: &index)
            case "--help", "-h":
                printUsageAndExit(code: 0)
            default:
                fputs("Unknown argument: \(arg)\n", stderr)
                printUsageAndExit(code: 2)
            }
            index += 1
        }

        return options
    }

    private static func parseValue(flag: String, index: inout Int) -> Double {
        let nextIndex = index + 1
        guard nextIndex < CommandLine.arguments.count,
              let value = Double(CommandLine.arguments[nextIndex]) else {
            fputs("Missing or invalid value for \(flag)\n", stderr)
            printUsageAndExit(code: 2)
        }
        index += 1
        return value
    }

    private static func printUsageAndExit(code: Int32) -> Never {
        let message = """
        SmoothScroll

        Usage:
          SmoothScroll
          SmoothScroll --headless [--speed N] [--smoothness 0..1] [--decay N] [--fps N] [--pointer-speed N]

        Modes:
          (default)      Starts menu bar app with on/off toggle and sliders
          --headless     Starts engine without menu bar UI (terminal mode)

        Options:
          --speed        Scroll strength per wheel notch (\(Int(TuningLimits.speed.lowerBound))..\((Int(TuningLimits.speed.upperBound))), default: \(EngineSettings.default.speed))
          --smoothness   Input blending amount (\(String(format: "%.2f", TuningLimits.smoothness.lowerBound))..\((String(format: "%.3f", TuningLimits.smoothness.upperBound))), default: \(EngineSettings.default.smoothness))
          --decay        Velocity damping per second (\(String(format: "%.1f", TuningLimits.decay.lowerBound))..\((String(format: "%.1f", TuningLimits.decay.upperBound))), default: \(EngineSettings.default.decay))
          --fps          Output event rate in Hz (\(Int(TuningLimits.fps.lowerBound))..\((Int(TuningLimits.fps.upperBound))), default: \(EngineSettings.default.fps))
          --pointer-speed Cursor tracking speed (\(String(format: "%.1f", TuningLimits.pointerSpeed.lowerBound))..\((String(format: "%.1f", TuningLimits.pointerSpeed.upperBound))), default: \(String(format: "%.1f", EngineSettings.default.pointerSpeed)))
        """

        if code == 0 {
            print(message)
        } else {
            fputs(message + "\n", stderr)
        }
        exit(code)
    }
}

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

final class LaunchAgentManager {
    private let label = "com.smoothscroll.agent"

    private var plistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    @discardableResult
    func enable(executablePath: String) -> Bool {
        guard FileManager.default.fileExists(atPath: executablePath) else {
            return false
        }

        do {
            try FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executablePath],
                "RunAtLoad": true,
                "ProcessType": "Interactive",
                "StandardOutPath": "/tmp/smoothscroll.out.log",
                "StandardErrorPath": "/tmp/smoothscroll.err.log"
            ]

            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        } catch {
            return false
        }

        let domain = "gui/\(getuid())"
        _ = runLaunchctl(["bootout", "\(domain)/\(label)"], ignoreFailure: true)

        guard runLaunchctl(["bootstrap", domain, plistURL.path], ignoreFailure: false) == 0 else {
            return false
        }

        _ = runLaunchctl(["enable", "\(domain)/\(label)"], ignoreFailure: true)
        _ = runLaunchctl(["kickstart", "-k", "\(domain)/\(label)"], ignoreFailure: true)
        return true
    }

    @discardableResult
    func disable() -> Bool {
        let domain = "gui/\(getuid())"
        _ = runLaunchctl(["bootout", "\(domain)/\(label)"], ignoreFailure: true)

        do {
            if FileManager.default.fileExists(atPath: plistURL.path) {
                try FileManager.default.removeItem(at: plistURL)
            }
            return true
        } catch {
            return false
        }
    }

    private func runLaunchctl(_ arguments: [String], ignoreFailure: Bool) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            if !ignoreFailure, process.terminationStatus != 0 {
                return process.terminationStatus
            }
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}

struct WindowSwitchTarget {
    let windowID: CGWindowID
    let processID: pid_t
    let appName: String
    let windowTitle: String

    var displayTitle: String {
        windowTitle.isEmpty ? appName : windowTitle
    }

    var detailTitle: String {
        windowTitle.isEmpty ? "Application Window" : appName
    }
}

struct WindowSwitchItem {
    let target: WindowSwitchTarget
    let appIcon: NSImage?
    let previewImage: NSImage?
}

enum WindowCatalog {
    private static let minimumWidth = 120.0
    private static let minimumHeight = 80.0
    private static let ignoredOwnerNames: Set<String> = ["Window Server", "Dock"]

    static func visibleWindows(
        excludingProcessID processID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> [WindowSwitchTarget] {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var seenWindowIDs = Set<CGWindowID>()
        var windows: [WindowSwitchTarget] = []

        for windowInfo in windowInfoList {
            guard let ownerPID = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else {
                continue
            }

            guard ownerPID != processID else {
                continue
            }

            let ownerName = (windowInfo[kCGWindowOwnerName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !ownerName.isEmpty, !ignoredOwnerNames.contains(ownerName) else {
                continue
            }

            let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else {
                continue
            }

            let alpha = (windowInfo[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
            guard alpha > 0.01 else {
                continue
            }

            guard let windowIDValue = (windowInfo[kCGWindowNumber as String] as? NSNumber)?.uint32Value else {
                continue
            }

            let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any]
            let width = (bounds?["Width"] as? NSNumber)?.doubleValue ?? 0
            let height = (bounds?["Height"] as? NSNumber)?.doubleValue ?? 0
            guard width >= minimumWidth, height >= minimumHeight else {
                continue
            }

            let windowID = CGWindowID(windowIDValue)
            guard seenWindowIDs.insert(windowID).inserted else {
                continue
            }

            let title = (windowInfo[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            windows.append(
                WindowSwitchTarget(
                    windowID: windowID,
                    processID: ownerPID,
                    appName: ownerName,
                    windowTitle: title
                )
            )
        }

        return windows
    }
}

enum WindowActivator {
    @discardableResult
    static func activate(_ target: WindowSwitchTarget) -> Bool {
        let runningApplication = NSRunningApplication(processIdentifier: target.processID)
        runningApplication?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])

        let applicationElement = AXUIElementCreateApplication(target.processID)
        let windows = copyWindowElements(from: applicationElement)

        if let matchingWindow = windows.first(where: { windowNumber(for: $0) == target.windowID }) {
            focus(window: matchingWindow, in: applicationElement)
            return true
        }

        if !target.windowTitle.isEmpty,
           let titleMatch = windows.first(where: { title(for: $0) == target.windowTitle }) {
            focus(window: titleMatch, in: applicationElement)
            return true
        }

        return runningApplication != nil
    }

    private static func copyWindowElements(from applicationElement: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success,
        let windows = value as? [AXUIElement] else {
            return []
        }

        return windows
    }

    private static func windowNumber(for window: AXUIElement) -> CGWindowID? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXWindowNumber" as CFString, &value) == .success,
              let number = value as? NSNumber else {
            return nil
        }

        return CGWindowID(number.uint32Value)
    }

    private static func title(for window: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success,
              let title = value as? String else {
            return nil
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func focus(window: AXUIElement, in applicationElement: AXUIElement) {
        _ = AXUIElementSetAttributeValue(
            applicationElement,
            kAXFrontmostAttribute as CFString,
            kCFBooleanTrue
        )
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }
}

enum WindowSnapshotProvider {
    private static let maximumPreviewSize = NSSize(width: 220, height: 140)

    static func makeItem(for target: WindowSwitchTarget) -> WindowSwitchItem {
        let appIcon = NSRunningApplication(processIdentifier: target.processID)?.icon
        return WindowSwitchItem(
            target: target,
            appIcon: appIcon,
            previewImage: capturePreview(for: target)
        )
    }

    private static func capturePreview(for target: WindowSwitchTarget) -> NSImage? {
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            target.windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }

        let originalSize = NSSize(width: cgImage.width, height: cgImage.height)
        let fittedSize = aspectFitSize(originalSize, within: maximumPreviewSize)
        let sourceImage = NSImage(cgImage: cgImage, size: originalSize)
        let image = NSImage(size: fittedSize)

        image.lockFocus()
        if let context = NSGraphicsContext.current {
            context.imageInterpolation = .high
        }
        sourceImage.draw(
            in: NSRect(origin: .zero, size: fittedSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1
        )
        image.unlockFocus()

        return image
    }
}

private final class WindowSwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class WindowSwitcherBlockerView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
}

@MainActor
private final class WindowSwitcherCardView: NSView {
    private let item: WindowSwitchItem
    private let previewContainer = NSView()
    private let previewImageView = NSImageView()
    private let placeholderIconView = NSImageView()
    private let badgeBackgroundView = NSView()
    private let badgeIconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var previewHeightConstraint: NSLayoutConstraint?
    var onClick: (() -> Void)?

    init(item: WindowSwitchItem) {
        self.item = item
        super.init(frame: .zero)
        configure()
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    func updateCardSize(width: CGFloat) {
        widthConstraint?.constant = width
        previewHeightConstraint?.constant = max(74, min(108, width * 0.64))
    }

    func setSelected(_ selected: Bool) {
        layer?.backgroundColor = (
            selected
                ? NSColor.white.withAlphaComponent(0.16)
                : NSColor.white.withAlphaComponent(0.05)
        ).cgColor
        layer?.borderColor = (
            selected
                ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.95)
                : NSColor.white.withAlphaComponent(0.08)
        ).cgColor
        layer?.borderWidth = selected ? 2 : 1
        alphaValue = selected ? 1.0 : 0.78
        titleLabel.textColor = selected ? .labelColor : .secondaryLabelColor
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true

        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.wantsLayer = true
        previewContainer.layer?.cornerRadius = 13
        previewContainer.layer?.masksToBounds = true
        previewContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor

        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewImageView.imageScaling = .scaleProportionallyUpOrDown

        placeholderIconView.translatesAutoresizingMaskIntoConstraints = false
        placeholderIconView.imageScaling = .scaleProportionallyUpOrDown

        badgeBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        badgeBackgroundView.wantsLayer = true
        badgeBackgroundView.layer?.cornerRadius = 12
        badgeBackgroundView.layer?.masksToBounds = true
        badgeBackgroundView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor

        badgeIconView.translatesAutoresizingMaskIntoConstraints = false
        badgeIconView.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail

        addSubview(previewContainer)
        previewContainer.addSubview(previewImageView)
        previewContainer.addSubview(placeholderIconView)
        previewContainer.addSubview(badgeBackgroundView)
        badgeBackgroundView.addSubview(badgeIconView)
        addSubview(titleLabel)

        widthConstraint = widthAnchor.constraint(equalToConstant: 156)
        heightConstraint = heightAnchor.constraint(equalToConstant: 146)
        previewHeightConstraint = previewContainer.heightAnchor.constraint(equalToConstant: 96)

        NSLayoutConstraint.activate([
            widthConstraint,
            heightConstraint,
            previewHeightConstraint
        ].compactMap { $0 } + [
            previewContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            previewContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            previewContainer.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            previewImageView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            previewImageView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

            placeholderIconView.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
            placeholderIconView.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),
            placeholderIconView.widthAnchor.constraint(equalToConstant: 40),
            placeholderIconView.heightAnchor.constraint(equalToConstant: 40),

            badgeBackgroundView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 8),
            badgeBackgroundView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: -8),
            badgeBackgroundView.widthAnchor.constraint(equalToConstant: 24),
            badgeBackgroundView.heightAnchor.constraint(equalToConstant: 24),

            badgeIconView.centerXAnchor.constraint(equalTo: badgeBackgroundView.centerXAnchor),
            badgeIconView.centerYAnchor.constraint(equalTo: badgeBackgroundView.centerYAnchor),
            badgeIconView.widthAnchor.constraint(equalToConstant: 16),
            badgeIconView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    private func render() {
        titleLabel.stringValue = item.target.displayTitle
        previewImageView.image = item.previewImage
        previewImageView.isHidden = item.previewImage == nil

        placeholderIconView.image = item.appIcon
        placeholderIconView.isHidden = item.previewImage != nil

        badgeIconView.image = item.appIcon
        badgeBackgroundView.isHidden = item.appIcon == nil || item.previewImage == nil
    }
}

@MainActor
final class WindowSwitcherOverlayController {
    private let panel: WindowSwitcherPanel
    private let blockerView = WindowSwitcherBlockerView()
    private let backdropView = NSView()
    private let chromeView = NSVisualEffectView()
    private let contentContainer = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let rowStackView = NSStackView()
    private var cardViews: [WindowSwitcherCardView] = []
    private var currentWindowIDs: [CGWindowID] = []
    private var containerWidthConstraint: NSLayoutConstraint?
    private var containerHeightConstraint: NSLayoutConstraint?
    var onItemActivated: ((Int) -> Void)?

    init() {
        panel = WindowSwitcherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel()
    }

    func show(session: WindowSwitchSession) {
        fitPanelToScreen()
        rebuildCardsIfNeeded(items: session.items)
        updateCardLayout(for: session.items.count)
        updateSelectionState(for: session)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.animationBehavior = .utilityWindow

        blockerView.translatesAutoresizingMaskIntoConstraints = false

        backdropView.translatesAutoresizingMaskIntoConstraints = false
        backdropView.wantsLayer = true
        backdropView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.14).cgColor

        chromeView.translatesAutoresizingMaskIntoConstraints = false
        chromeView.material = .hudWindow
        chromeView.blendingMode = .withinWindow
        chromeView.state = .active
        chromeView.wantsLayer = true
        chromeView.layer?.cornerRadius = 26
        chromeView.layer?.masksToBounds = true
        chromeView.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        chromeView.layer?.borderWidth = 1

        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.alignment = .center
        detailLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

        rowStackView.translatesAutoresizingMaskIntoConstraints = false
        rowStackView.orientation = .horizontal
        rowStackView.alignment = .top
        rowStackView.distribution = .fill
        rowStackView.spacing = 12

        blockerView.addSubview(backdropView)
        blockerView.addSubview(chromeView)
        chromeView.addSubview(contentContainer)
        contentContainer.addSubview(rowStackView)
        contentContainer.addSubview(titleLabel)
        contentContainer.addSubview(detailLabel)
        panel.contentView = blockerView

        containerWidthConstraint = contentContainer.widthAnchor.constraint(equalToConstant: 760)
        containerHeightConstraint = contentContainer.heightAnchor.constraint(equalToConstant: 246)

        NSLayoutConstraint.activate([
            backdropView.leadingAnchor.constraint(equalTo: blockerView.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: blockerView.trailingAnchor),
            backdropView.topAnchor.constraint(equalTo: blockerView.topAnchor),
            backdropView.bottomAnchor.constraint(equalTo: blockerView.bottomAnchor),

            chromeView.centerXAnchor.constraint(equalTo: blockerView.centerXAnchor),
            chromeView.centerYAnchor.constraint(equalTo: blockerView.centerYAnchor),

            contentContainer.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: chromeView.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: chromeView.bottomAnchor),

            rowStackView.leadingAnchor.constraint(greaterThanOrEqualTo: contentContainer.leadingAnchor, constant: 24),
            rowStackView.trailingAnchor.constraint(lessThanOrEqualTo: contentContainer.trailingAnchor, constant: -24),
            rowStackView.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 24),
            rowStackView.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: rowStackView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -20),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            detailLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 20),
            detailLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -20),
            detailLabel.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -18)
        ] + [containerWidthConstraint, containerHeightConstraint].compactMap { $0 })
    }

    private func rebuildCardsIfNeeded(items: [WindowSwitchItem]) {
        let windowIDs = items.map { $0.target.windowID }
        guard windowIDs != currentWindowIDs else {
            return
        }

        currentWindowIDs = windowIDs

        for cardView in cardViews {
            rowStackView.removeArrangedSubview(cardView)
            cardView.removeFromSuperview()
        }

        cardViews = items.map { item in
            let cardView = WindowSwitcherCardView(item: item)
            cardView.onClick = { [weak self] in
                guard let self else {
                    return
                }
                guard let index = self.cardViews.firstIndex(where: { $0 === cardView }) else {
                    return
                }
                self.onItemActivated?(index)
            }
            rowStackView.addArrangedSubview(cardView)
            return cardView
        }
    }

    private func updateCardLayout(for itemCount: Int) {
        guard itemCount > 0 else {
            return
        }

        let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
        let maxPanelWidth = max(420, (visibleFrame?.width ?? 1100) - 80)
        let horizontalPadding: CGFloat = 48
        let spacing = rowStackView.spacing * CGFloat(max(0, itemCount - 1))
        let availableCardWidth = (maxPanelWidth - horizontalPadding - spacing) / CGFloat(itemCount)
        let cardWidth = max(112, min(160, floor(availableCardWidth)))
        let panelWidth = min(
            maxPanelWidth,
            horizontalPadding + spacing + (cardWidth * CGFloat(itemCount))
        )

        for cardView in cardViews {
            cardView.updateCardSize(width: cardWidth)
        }

        containerWidthConstraint?.constant = max(420, panelWidth)
        containerHeightConstraint?.constant = 246
    }

    private func updateSelectionState(for session: WindowSwitchSession) {
        for (index, cardView) in cardViews.enumerated() {
            cardView.setSelected(index == session.selectedIndex)
        }

        let selectedItem = session.selectedItem
        titleLabel.stringValue = selectedItem.target.displayTitle
        detailLabel.stringValue = "\(selectedItem.target.appName)  •  Window \(session.selectedIndex + 1) of \(session.items.count)"
    }

    private func fitPanelToScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        panel.setFrame(screen.frame, display: false)
    }
}

struct WindowSwitchSession {
    let items: [WindowSwitchItem]
    var selectedIndex: Int

    var windows: [WindowSwitchTarget] {
        items.map(\.target)
    }

    var selectedItem: WindowSwitchItem {
        items[selectedIndex]
    }

    var selectedWindow: WindowSwitchTarget {
        selectedItem.target
    }
}

@MainActor
final class WindowSwitcherManager {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var running = false
    private var commandIsDown = false
    private var activeSession: WindowSwitchSession?

    private lazy var overlayController: WindowSwitcherOverlayController = {
        let controller = WindowSwitcherOverlayController()
        controller.onItemActivated = { [weak self] index in
            self?.activateItem(at: index)
        }
        return controller
    }()

    func start(promptForPermissions: Bool) -> Bool {
        guard !running else {
            return true
        }

        guard requestAccessibilityTrust(prompt: promptForPermissions) else {
            return false
        }

        guard setupEventTap() else {
            return false
        }

        running = true
        return true
    }

    func stop() {
        guard running else {
            return
        }

        running = false
        commandIsDown = false
        finishSwitching(commitSelection: false)

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }

        if let tap {
            CFMachPortInvalidate(tap)
            self.tap = nil
        }
    }

    func isRunning() -> Bool {
        running
    }

    private func requestAccessibilityTrust(prompt: Bool) -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        guard prompt else {
            return false
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func setupEventTap() -> Bool {
        let mask =
            CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.keyUp.rawValue) |
            CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: windowSwitcherTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        self.tap = tap
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .flagsChanged:
            let isCommandDown = event.flags.contains(.maskCommand)
            let commandWasDown = commandIsDown
            commandIsDown = isCommandDown

            if activeSession != nil, commandWasDown, !isCommandDown {
                finishSwitching(commitSelection: true)
                return nil
            }

            return Unmanaged.passRetained(event)

        case .keyDown:
            if keyCode == KeyboardKeyCode.tab, event.flags.contains(.maskCommand) {
                commandIsDown = true
                cycleSelection(reverse: event.flags.contains(.maskShift))
                return nil
            }

            if activeSession != nil, keyCode == KeyboardKeyCode.escape {
                finishSwitching(commitSelection: false)
                return nil
            }

            return Unmanaged.passRetained(event)

        case .keyUp:
            if activeSession != nil, keyCode == KeyboardKeyCode.tab {
                return nil
            }

            return Unmanaged.passRetained(event)

        default:
            return Unmanaged.passRetained(event)
        }
    }

    private func cycleSelection(reverse: Bool) {
        if var session = activeSession {
            session.selectedIndex = advancedIndex(
                from: session.selectedIndex,
                total: session.windows.count,
                reverse: reverse
            )
            activeSession = session
            presentCurrentSelection()
            return
        }

        let windows = WindowCatalog.visibleWindows()
        guard windows.count > 1 else {
            return
        }

        let initialIndex = reverse ? windows.count - 1 : 1
        let items = windows.map(WindowSnapshotProvider.makeItem(for:))
        activeSession = WindowSwitchSession(items: items, selectedIndex: initialIndex)
        presentCurrentSelection()
    }

    private func presentCurrentSelection() {
        guard let session = activeSession else {
            overlayController.hide()
            return
        }

        overlayController.show(session: session)
    }

    private func finishSwitching(commitSelection: Bool) {
        let selectedWindow = activeSession?.selectedWindow
        activeSession = nil

        overlayController.hide()

        guard commitSelection, let selectedWindow else {
            return
        }

        _ = WindowActivator.activate(selectedWindow)
    }

    private func activateItem(at index: Int) {
        guard var session = activeSession, session.items.indices.contains(index) else {
            return
        }

        session.selectedIndex = index
        activeSession = session
        finishSwitching(commitSelection: true)
    }

    private func advancedIndex(from currentIndex: Int, total: Int, reverse: Bool) -> Int {
        guard total > 0 else {
            return 0
        }

        let delta = reverse ? -1 : 1
        return (currentIndex + delta + total) % total
    }
}

final class KeyboardCleaningManager {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var running = false

    func start(promptForPermissions: Bool) -> Bool {
        guard !running else {
            return true
        }

        guard requestAccessibilityTrust(prompt: promptForPermissions) else {
            return false
        }

        guard setupEventTap() else {
            return false
        }

        running = true
        return true
    }

    func stop() {
        guard running else {
            return
        }

        running = false

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }

        if let tap {
            CFMachPortInvalidate(tap)
            self.tap = nil
        }
    }

    private func requestAccessibilityTrust(prompt: Bool) -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        guard prompt else {
            return false
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func setupEventTap() -> Bool {
        var keyEventTypes: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        if let systemDefinedType = CGEventType(rawValue: 14) {
            keyEventTypes.append(systemDefinedType)
        }
        let mask = keyEventTypes.reduce(CGEventMask(0)) { partialMask, type in
            partialMask | CGEventMask(1 << type.rawValue)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyboardCleaningTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        self.tap = tap
        self.runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let isSystemDefined = CGEventType(rawValue: 14) == type
        switch type {
        case .keyDown, .keyUp, .flagsChanged:
            return nil
        default:
            return isSystemDefined ? nil : Unmanaged.passRetained(event)
        }
    }
}

final class ScrollEngine {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "smoothscroll.engine", qos: .userInteractive)
    private let syntheticEventMarker: Int64 = 0x53534D4F4F5448 // "SSMOOTH"

    private var settings: EngineSettings
    private var enabled: Bool = true
    private var running = false
    var onToggleEnabledRequested: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var timer: DispatchSourceTimer?

    private var targetVelocityY: Double = 0
    private var currentVelocityY: Double = 0
    private var remainderY: Double = 0

    private var targetVelocityX: Double = 0
    private var currentVelocityX: Double = 0
    private var remainderX: Double = 0

    private var lastTickNanos: UInt64 = DispatchTime.now().uptimeNanoseconds

    init(settings: EngineSettings) {
        self.settings = settings.clamped
    }

    func start(promptForPermissions: Bool) -> Bool {
        lock.lock()
        if running {
            lock.unlock()
            return true
        }
        lock.unlock()

        guard requestAccessibilityTrust(prompt: promptForPermissions) else {
            return false
        }

        guard setupEventTap() else {
            return false
        }

        setupTimer()

        lock.lock()
        running = true
        lock.unlock()

        return true
    }

    func stop() {
        lock.lock()
        let wasRunning = running
        running = false
        lock.unlock()

        guard wasRunning else { return }

        timer?.cancel()
        timer = nil

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }

        if let tap {
            CFMachPortInvalidate(tap)
            self.tap = nil
        }
    }

    func isRunning() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    func setEnabled(_ enabled: Bool) {
        lock.lock()
        self.enabled = enabled
        lock.unlock()
    }

    func updateSettings(_ settings: EngineSettings) {
        let newSettings = settings.clamped

        var fpsChanged = false
        lock.lock()
        fpsChanged = abs(self.settings.fps - newSettings.fps) > 0.001
        self.settings = newSettings
        lock.unlock()

        if fpsChanged {
            rescheduleTimer(fps: newSettings.fps)
        }
    }

    private func requestAccessibilityTrust(prompt: Bool) -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        guard prompt else {
            return false
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func setupTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        self.timer = timer
        rescheduleTimer(fps: settings.fps)

        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
    }

    private func rescheduleTimer(fps: Double) {
        guard let timer else { return }
        let interval = max(1.0 / 240.0, 1.0 / fps)
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .nanoseconds(250_000)
        )
    }

    private func setupEventTap() -> Bool {
        let scrollMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let otherMouseDownMask = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
        let otherMouseUpMask = CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
        let mask = scrollMask | otherMouseDownMask | otherMouseUpMask

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        self.tap = tap
        self.runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        if type == .otherMouseDown || type == .otherMouseUp {
            lock.lock()
            let localSettings = settings
            lock.unlock()
            return handleMappedMouseButtonEvent(type: type, event: event, settings: localSettings)
        }

        if type != .scrollWheel {
            return Unmanaged.passRetained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker {
            return Unmanaged.passRetained(event)
        }

        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
        if isContinuous == 1 {
            return Unmanaged.passRetained(event)
        }

        lock.lock()
        let isEnabled = enabled
        let localSettings = settings
        lock.unlock()

        guard isEnabled else {
            return Unmanaged.passRetained(event)
        }

        let rawY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let rawX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)

        if rawY == 0, rawX == 0 {
            return Unmanaged.passRetained(event)
        }

        let impulseScale = localSettings.speed * 18.0
        let impulseY = Double(rawY) * impulseScale
        let impulseX = Double(rawX) * impulseScale
        let smoothingGain = 1.0 - (localSettings.smoothness * 0.75)

        lock.lock()
        targetVelocityY += impulseY * smoothingGain
        targetVelocityX += impulseX * smoothingGain
        lock.unlock()

        return nil
    }

    private func handleMappedMouseButtonEvent(
        type: CGEventType,
        event: CGEvent,
        settings: EngineSettings
    ) -> Unmanaged<CGEvent>? {
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        let mapping = settings.mapping(forMouseButtonNumber: buttonNumber)
        let action = mapping.action

        guard action != .passthrough else {
            return Unmanaged.passRetained(event)
        }

        if type == .otherMouseDown {
            triggerMouseButtonAction(action, keyboardKey: mapping.keyboardKey)
        }

        return nil
    }

    private func triggerMouseButtonAction(_ action: MouseButtonAction, keyboardKey: MouseButtonKeyboardKey) {
        switch action {
        case .passthrough:
            break
        case .back:
            postKeyboardShortcut(keyCode: 33, flags: .maskCommand)
        case .forward:
            postKeyboardShortcut(keyCode: 30, flags: .maskCommand)
        case .toggleSmoothScroll:
            onToggleEnabledRequested?()
        case .keyboardKey:
            postKeyboardShortcut(keyCode: keyboardKey.keyCode, flags: keyboardKey.flags)
        }
    }

    private func postKeyboardShortcut(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func tick() {
        let now = DispatchTime.now().uptimeNanoseconds
        let dt = max(1.0 / 240.0, min(Double(now - lastTickNanos) / 1_000_000_000.0, 1.0 / 20.0))
        lastTickNanos = now

        lock.lock()

        if !running || !enabled {
            lock.unlock()
            return
        }

        let localSettings = settings
        let followRate = 7.0 + (1.0 - localSettings.smoothness) * 30.0
        currentVelocityY += (targetVelocityY - currentVelocityY) * min(1.0, followRate * dt)
        currentVelocityX += (targetVelocityX - currentVelocityX) * min(1.0, followRate * dt)

        let targetDecay = exp(-max(1.0, localSettings.decay * 0.35) * dt)
        let velocityDecay = exp(-localSettings.decay * dt)

        targetVelocityY *= targetDecay
        targetVelocityX *= targetDecay
        currentVelocityY *= velocityDecay
        currentVelocityX *= velocityDecay

        let stepY = currentVelocityY * dt + remainderY
        let stepX = currentVelocityX * dt + remainderX
        let emitY = Int32(stepY.rounded(.towardZero))
        let emitX = Int32(stepX.rounded(.towardZero))

        remainderY = stepY - Double(emitY)
        remainderX = stepX - Double(emitX)

        if abs(targetVelocityY) < 0.2,
           abs(currentVelocityY) < 0.2,
           abs(targetVelocityX) < 0.2,
           abs(currentVelocityX) < 0.2 {
            targetVelocityY = 0
            currentVelocityY = 0
            remainderY = 0

            targetVelocityX = 0
            currentVelocityX = 0
            remainderX = 0
        }

        lock.unlock()

        if emitY != 0 || emitX != 0 {
            postPixelScroll(deltaY: emitY, deltaX: emitX)
        }
    }

    private func postPixelScroll(deltaY: Int32, deltaX: Int32) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ) else {
            return
        }

        event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        event.post(tap: .cghidEventTap)
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passRetained(event)
    }

    let engine = Unmanaged<ScrollEngine>.fromOpaque(userInfo).takeUnretainedValue()
    return engine.handleEvent(type: type, event: event)
}

private let keyboardCleaningTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passRetained(event)
    }

    let manager = Unmanaged<KeyboardCleaningManager>.fromOpaque(userInfo).takeUnretainedValue()
    return manager.handleEvent(type: type, event: event)
}

private let windowSwitcherTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passRetained(event)
    }

    let manager = Unmanaged<WindowSwitcherManager>.fromOpaque(userInfo).takeUnretainedValue()
    return MainActor.assumeIsolated {
        manager.handleEvent(type: type, event: event)
    }
}

@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let keyboardCleaningAutoDisableSeconds: TimeInterval = 120.0

    private var settings: EngineSettings
    private var engineEnabled: Bool
    private var windowSwitcherEnabled: Bool
    private var keyboardCleaningEnabled = false

    private let engine: ScrollEngine
    private let windowSwitcherManager = WindowSwitcherManager()
    private let keyboardCleaningManager = KeyboardCleaningManager()
    private let launchAgentManager = LaunchAgentManager()

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    private var enabledItem: NSMenuItem?
    private var windowSwitcherItem: NSMenuItem?
    private var keyboardCleaningItem: NSMenuItem?
    private var saveSettingsItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?
    private var keyboardCleaningAutoDisableWorkItem: DispatchWorkItem?

    private var speedSlider: NSSlider?
    private var pointerSpeedSlider: NSSlider?
    private var smoothnessSlider: NSSlider?
    private var decaySlider: NSSlider?
    private var fpsSlider: NSSlider?
    private var sideButtonPrimaryItem: NSMenuItem?
    private var sideButtonSecondaryItem: NSMenuItem?

    private var speedLabel: NSTextField?
    private var pointerSpeedLabel: NSTextField?
    private var smoothnessLabel: NSTextField?
    private var decayLabel: NSTextField?
    private var fpsLabel: NSTextField?

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

    @objc private func toggleEngine(_ sender: NSMenuItem) {
        engineEnabled.toggle()
        SettingsStore.saveEnabled(engineEnabled)
        applyEngineEnabledState(promptForPermissions: true)
        updateMenuState()
    }

    @objc private func toggleWindowSwitcher(_ sender: NSMenuItem) {
        windowSwitcherEnabled.toggle()
        SettingsStore.saveWindowSwitcherEnabled(windowSwitcherEnabled)
        applyWindowSwitcherEnabledState(promptForPermissions: true)
        updateMenuState()
    }

    @objc private func toggleKeyboardCleaning(_ sender: NSMenuItem) {
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

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
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

    @objc private func speedChanged(_ sender: NSSlider) {
        settings.speed = sender.doubleValue.rounded()
        sender.doubleValue = settings.speed
        saveAndApplySettings()
    }

    @objc private func smoothnessChanged(_ sender: NSSlider) {
        settings.smoothness = (sender.doubleValue * 100).rounded() / 100
        sender.doubleValue = settings.smoothness
        saveAndApplySettings()
    }

    @objc private func pointerSpeedChanged(_ sender: NSSlider) {
        settings.pointerSpeed = (sender.doubleValue * 10).rounded() / 10
        sender.doubleValue = settings.pointerSpeed
        saveAndApplySettings()
    }

    @objc private func decayChanged(_ sender: NSSlider) {
        settings.decay = (sender.doubleValue * 10).rounded() / 10
        sender.doubleValue = settings.decay
        saveAndApplySettings()
    }

    @objc private func fpsChanged(_ sender: NSSlider) {
        settings.fps = (sender.doubleValue / 5).rounded() * 5
        sender.doubleValue = settings.fps
        saveAndApplySettings()
    }

    @objc private func sideButtonActionChanged(_ sender: NSMenuItem) {
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

    @objc private func saveSettingsNow(_ sender: NSMenuItem) {
        persistSettings()
        sender.title = "Saved ✓"
        sender.isEnabled = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.saveSettingsItem?.title = "Save Settings"
            self?.saveSettingsItem?.isEnabled = true
        }
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    private func constructMenuBarUI() {
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

    private func applyEngineEnabledState(promptForPermissions: Bool) {
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

    private func applyWindowSwitcherEnabledState(promptForPermissions: Bool) {
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

    private func toggleEngineFromMouseButton() {
        engineEnabled.toggle()
        SettingsStore.saveEnabled(engineEnabled)
        applyEngineEnabledState(promptForPermissions: false)
        updateMenuState()
    }

    private func saveAndApplySettings() {
        settings = settings.clamped
        persistSettings()
        applySystemPointerSpeed()
        engine.updateSettings(settings)
        updateMenuState()
    }

    private func applySystemPointerSpeed() {
        PointerSpeedManager.apply(settings.pointerSpeed)
    }

    private func persistSettings() {
        settings = settings.clamped
        SettingsStore.saveSettings(settings)
        SettingsStore.saveEnabled(engineEnabled)
        SettingsStore.saveWindowSwitcherEnabled(windowSwitcherEnabled)
    }

    private func setSideButtonAction(_ action: MouseButtonAction, for slot: SideMouseButtonSlot) {
        switch slot {
        case .primary:
            settings.sideButtonPrimaryAction = action
        case .secondary:
            settings.sideButtonSecondaryAction = action
        }
    }

    private func setSideButtonKeyboardKey(_ key: MouseButtonKeyboardKey, for slot: SideMouseButtonSlot) {
        switch slot {
        case .primary:
            settings.sideButtonPrimaryKeyboardKey = key
        case .secondary:
            settings.sideButtonSecondaryKeyboardKey = key
        }
    }

    private func updateMouseButtonMenuStates() {
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

    private func updateMouseButtonMenuState(
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

    private func scheduleKeyboardCleaningAutoDisable() {
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

    private func disableKeyboardCleaning(showTimeoutAlert: Bool) {
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

    private func updateMenuState() {
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

    private func resolveExecutablePath() -> String {
        let rawPath = CommandLine.arguments[0]
        if rawPath.hasPrefix("/") {
            return URL(fileURLWithPath: rawPath).standardizedFileURL.path
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return URL(fileURLWithPath: rawPath, relativeTo: cwd).standardizedFileURL.path
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }
}

@main
struct SmoothScroll {
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
