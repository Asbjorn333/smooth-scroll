import Darwin
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
    // These legacy IOKit entry points still control the live pointer acceleration path.
    // Resolve them dynamically so builds stay warning-free while preserving runtime behavior.
    private static let runtimeAPI = HIDRuntimeAPI()

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
        guard let getAccelerationWithKey = runtimeAPI.getAccelerationWithKey else {
            return nil
        }

        return withHIDEventStatusHandle { handle in
            for key in hidAccelerationKeys {
                var value = 0.0
                if getAccelerationWithKey(handle, key as CFString, &value) == KERN_SUCCESS {
                    return clampValue(value, to: systemRange)
                }
            }
            return nil
        }
    }

    private static func applyRuntimeSystemSpeed(_ value: Double) {
        guard let setAccelerationWithKey = runtimeAPI.setAccelerationWithKey else {
            return
        }

        _ = withHIDEventStatusHandle { handle in
            for key in hidAccelerationKeys {
                _ = setAccelerationWithKey(handle, key as CFString, value)
            }
            return true
        }
    }

    private static func withHIDEventStatusHandle<T>(_ body: (NXEventHandle) -> T?) -> T? {
        guard let openEventStatus = runtimeAPI.openEventStatus,
              let closeEventStatus = runtimeAPI.closeEventStatus else {
            return nil
        }

        let handle = openEventStatus()
        guard handle != 0 else {
            return nil
        }
        defer {
            closeEventStatus(handle)
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

private struct HIDRuntimeAPI {
    typealias OpenEventStatusFn = @convention(c) () -> NXEventHandle
    typealias CloseEventStatusFn = @convention(c) (NXEventHandle) -> Void
    typealias GetAccelerationWithKeyFn = @convention(c) (
        io_connect_t,
        CFString,
        UnsafeMutablePointer<Double>
    ) -> kern_return_t
    typealias SetAccelerationWithKeyFn = @convention(c) (
        io_connect_t,
        CFString,
        Double
    ) -> kern_return_t

    let openEventStatus: OpenEventStatusFn?
    let closeEventStatus: CloseEventStatusFn?
    let getAccelerationWithKey: GetAccelerationWithKeyFn?
    let setAccelerationWithKey: SetAccelerationWithKeyFn?

    init() {
        let handle = dlopen("/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit", RTLD_LAZY)
        openEventStatus = Self.loadSymbol(named: "NXOpenEventStatus", from: handle)
        closeEventStatus = Self.loadSymbol(named: "NXCloseEventStatus", from: handle)
        getAccelerationWithKey = Self.loadSymbol(named: "IOHIDGetAccelerationWithKey", from: handle)
        setAccelerationWithKey = Self.loadSymbol(named: "IOHIDSetAccelerationWithKey", from: handle)
    }

    private static func loadSymbol<Function>(named symbolName: String, from handle: UnsafeMutableRawPointer?) -> Function? {
        guard let handle, let symbol = dlsym(handle, symbolName) else {
            return nil
        }

        return unsafeBitCast(symbol, to: Function.self)
    }
}
