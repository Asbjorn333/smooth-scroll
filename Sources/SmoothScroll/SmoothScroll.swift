import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import IOKit
import IOKit.hidsystem

enum TuningLimits {
    static let speed: ClosedRange<Double> = 1.0...1000.0
    static let smoothness: ClosedRange<Double> = 0.0...0.995
    static let decay: ClosedRange<Double> = 0.1...120.0
    static let fps: ClosedRange<Double> = 30.0...360.0
    static let pointerSpeed: ClosedRange<Double> = 0.0...10.0
}

private func clampValue(_ value: Double, to range: ClosedRange<Double>) -> Double {
    max(range.lowerBound, min(value, range.upperBound))
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
    private static let systemRange: ClosedRange<Double> = 0.0...10.0

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

    static let `default` = EngineSettings(
        speed: 100.0,
        smoothness: 0.80,
        decay: 28.0,
        fps: 120.0,
        pointerSpeed: PointerSpeedManager.currentSystemValue()
    )

    var clamped: EngineSettings {
        EngineSettings(
            speed: clampValue(speed, to: TuningLimits.speed),
            smoothness: clampValue(smoothness, to: TuningLimits.smoothness),
            decay: clampValue(decay, to: TuningLimits.decay),
            fps: clampValue(fps, to: TuningLimits.fps),
            pointerSpeed: clampValue(pointerSpeed, to: TuningLimits.pointerSpeed)
        )
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
    private static let keySpeed = "smoothscroll.speed"
    private static let keySmoothness = "smoothscroll.smoothness"
    private static let keyDecay = "smoothscroll.decay"
    private static let keyFPS = "smoothscroll.fps"
    private static let keyPointerSpeed = "smoothscroll.pointerSpeed"
    private static let keyDefaultsVersion = "smoothscroll.defaultsVersion"
    private static let currentDefaultsVersion = 3

    static func loadSettings() -> EngineSettings {
        let defaults = UserDefaults.standard
        migrateDefaultsIfNeeded(defaults)

        let speed = defaults.object(forKey: keySpeed) as? Double ?? EngineSettings.default.speed
        let smoothness = defaults.object(forKey: keySmoothness) as? Double ?? EngineSettings.default.smoothness
        let decay = defaults.object(forKey: keyDecay) as? Double ?? EngineSettings.default.decay
        let fps = defaults.object(forKey: keyFPS) as? Double ?? EngineSettings.default.fps
        let pointerSpeed = defaults.object(forKey: keyPointerSpeed) as? Double ?? PointerSpeedManager.currentSystemValue()

        return EngineSettings(
            speed: speed,
            smoothness: smoothness,
            decay: decay,
            fps: fps,
            pointerSpeed: pointerSpeed
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

    private static func migrateDefaultsIfNeeded(_ defaults: UserDefaults) {
        let version = defaults.integer(forKey: keyDefaultsVersion)
        guard version < currentDefaultsVersion else {
            return
        }

        let hadAnySavedValues = defaults.object(forKey: keySpeed) != nil ||
            defaults.object(forKey: keySmoothness) != nil ||
            defaults.object(forKey: keyDecay) != nil ||
            defaults.object(forKey: keyFPS) != nil ||
            defaults.object(forKey: keyPointerSpeed) != nil

        if !hadAnySavedValues || hasLegacyDefaultValues(defaults) {
            defaults.set(EngineSettings.default.speed, forKey: keySpeed)
            defaults.set(EngineSettings.default.smoothness, forKey: keySmoothness)
            defaults.set(EngineSettings.default.decay, forKey: keyDecay)
            defaults.set(EngineSettings.default.fps, forKey: keyFPS)
            defaults.set(EngineSettings.default.pointerSpeed, forKey: keyPointerSpeed)
        }

        defaults.set(currentDefaultsVersion, forKey: keyDefaultsVersion)
    }

    private static func hasLegacyDefaultValues(_ defaults: UserDefaults) -> Bool {
        let legacy = EngineSettings(
            speed: 42.0,
            smoothness: 0.75,
            decay: 12.0,
            fps: 120.0,
            pointerSpeed: PointerSpeedManager.currentSystemValue()
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
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)

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

@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let keyboardCleaningAutoDisableSeconds: TimeInterval = 120.0

    private var settings: EngineSettings
    private var engineEnabled: Bool
    private var keyboardCleaningEnabled = false

    private let engine: ScrollEngine
    private let keyboardCleaningManager = KeyboardCleaningManager()
    private let launchAgentManager = LaunchAgentManager()

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    private var enabledItem: NSMenuItem?
    private var keyboardCleaningItem: NSMenuItem?
    private var saveSettingsItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?
    private var keyboardCleaningAutoDisableWorkItem: DispatchWorkItem?

    private var speedSlider: NSSlider?
    private var pointerSpeedSlider: NSSlider?
    private var smoothnessSlider: NSSlider?
    private var decaySlider: NSSlider?
    private var fpsSlider: NSSlider?

    private var speedLabel: NSTextField?
    private var pointerSpeedLabel: NSTextField?
    private var smoothnessLabel: NSTextField?
    private var decayLabel: NSTextField?
    private var fpsLabel: NSTextField?

    init(settings: EngineSettings, enabled: Bool) {
        self.settings = settings.clamped
        self.engineEnabled = enabled
        self.engine = ScrollEngine(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        constructMenuBarUI()
        applySystemPointerSpeed()
        applyEngineEnabledState(promptForPermissions: true)
        updateMenuState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        disableKeyboardCleaning(showTimeoutAlert: false)
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

        keyboardCleaningItem = NSMenuItem(
            title: "Enable Keyboard Cleaning",
            action: #selector(toggleKeyboardCleaning(_:)),
            keyEquivalent: ""
        )
        keyboardCleaningItem?.target = self
        if let keyboardCleaningItem { menu.addItem(keyboardCleaningItem) }

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
        keyboardCleaningItem?.state = keyboardCleaningEnabled ? .on : .off
        keyboardCleaningItem?.title = keyboardCleaningEnabled ? "Disable Keyboard Cleaning" : "Enable Keyboard Cleaning"

        speedSlider?.doubleValue = settings.speed
        pointerSpeedSlider?.doubleValue = settings.pointerSpeed
        smoothnessSlider?.doubleValue = settings.smoothness
        decaySlider?.doubleValue = settings.decay
        fpsSlider?.doubleValue = settings.fps

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

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = MenuBarController(settings: settings, enabled: enabled)
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
