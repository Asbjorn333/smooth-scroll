@preconcurrency import ApplicationServices
@preconcurrency import CoreGraphics
import Foundation

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

private let keyboardCleaningTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passRetained(event)
    }

    let manager = Unmanaged<KeyboardCleaningManager>.fromOpaque(userInfo).takeUnretainedValue()
    return manager.handleEvent(type: type, event: event)
}
