import Foundation
import IOKit
import IOKit.hidsystem

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
