@preconcurrency import ApplicationServices
@preconcurrency import CoreGraphics
import Foundation

final class ScrollEngine {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "smoothscroll.engine", qos: .userInteractive)
    private let syntheticEventMarker: Int64 = 0x53534D4F4F5448

    private var settings: EngineSettings
    private var enabled = true
    private var running = false
    var onToggleEnabledRequested: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var timer: DispatchSourceTimer?

    private var targetVelocityY = 0.0
    private var currentVelocityY = 0.0
    private var remainderY = 0.0

    private var targetVelocityX = 0.0
    private var currentVelocityX = 0.0
    private var remainderX = 0.0

    private var lastTickNanos = DispatchTime.now().uptimeNanoseconds

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
            callback: scrollEngineTapCallback,
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

private let scrollEngineTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passRetained(event)
    }

    let engine = Unmanaged<ScrollEngine>.fromOpaque(userInfo).takeUnretainedValue()
    return engine.handleEvent(type: type, event: event)
}
