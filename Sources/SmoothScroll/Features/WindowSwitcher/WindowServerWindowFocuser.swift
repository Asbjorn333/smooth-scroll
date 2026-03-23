import Carbon
import Darwin
@preconcurrency import CoreGraphics

// This uses private WindowServer entry points as a last-mile fallback to focus
// a specific window reliably across spaces and displays.
enum WindowServerWindowFocuser {
    private static let runtimeAPI = SkyLightRuntimeAPI()

    @discardableResult
    static func focus(processID: pid_t, windowID: CGWindowID) -> Bool {
        guard let getProcessForPID = runtimeAPI.getProcessForPID,
              let setFrontProcessWithOptions = runtimeAPI.setFrontProcessWithOptions,
              let postEventRecordTo = runtimeAPI.postEventRecordTo else {
            return false
        }

        var processSerialNumber = ProcessSerialNumber()
        guard getProcessForPID(processID, &processSerialNumber) == noErr else {
            return false
        }

        let frontResult = setFrontProcessWithOptions(
            &processSerialNumber,
            windowID,
            SLPSMode.userGenerated.rawValue
        )

        let makeKeyResult = postMakeKeyWindowEvents(
            to: &processSerialNumber,
            windowID: windowID,
            postEventRecordTo: postEventRecordTo
        )

        return frontResult == .success || makeKeyResult
    }

    private static func postMakeKeyWindowEvents(
        to processSerialNumber: inout ProcessSerialNumber,
        windowID: CGWindowID,
        postEventRecordTo: SkyLightRuntimeAPI.PostEventRecordToFn
    ) -> Bool {
        var record = [UInt8](repeating: 0, count: 0xF8)
        record[0x04] = 0xF8
        record[0x3A] = 0x10

        withUnsafeBytes(of: windowID) { windowIDBytes in
            guard let source = windowIDBytes.baseAddress else {
                return
            }

            record.withUnsafeMutableBytes { recordBytes in
                guard let destination = recordBytes.baseAddress?.advanced(by: 0x3C) else {
                    return
                }

                memcpy(destination, source, MemoryLayout<CGWindowID>.size)
            }
        }

        for index in 0x20..<(0x20 + 0x10) {
            record[index] = 0xFF
        }

        var succeeded = false
        for phase: UInt8 in [0x01, 0x02] {
            record[0x08] = phase
            let result = record.withUnsafeMutableBufferPointer { buffer in
                guard let pointer = buffer.baseAddress else {
                    return CGError.failure
                }

                return postEventRecordTo(&processSerialNumber, pointer)
            }

            succeeded = succeeded || result == .success
        }

        return succeeded
    }
}

private enum SLPSMode: UInt32 {
    case userGenerated = 0x200
}

private struct SkyLightRuntimeAPI {
    typealias GetProcessForPIDFn = @convention(c) (
        pid_t,
        UnsafeMutablePointer<ProcessSerialNumber>
    ) -> OSStatus
    typealias SetFrontProcessWithOptionsFn = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>,
        CGWindowID,
        UInt32
    ) -> CGError
    typealias PostEventRecordToFn = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>,
        UnsafeMutablePointer<UInt8>
    ) -> CGError

    let getProcessForPID: GetProcessForPIDFn?
    let setFrontProcessWithOptions: SetFrontProcessWithOptionsFn?
    let postEventRecordTo: PostEventRecordToFn?

    init() {
        let hiServicesHandle = dlopen(
            "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/Versions/Current/HIServices",
            RTLD_LAZY
        )
        let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/Current/SkyLight",
            RTLD_LAZY
        )

        getProcessForPID = Self.loadSymbol(
            named: "GetProcessForPID",
            from: hiServicesHandle
        )
        setFrontProcessWithOptions = Self.loadSymbol(
            named: "_SLPSSetFrontProcessWithOptions",
            from: handle
        )
        postEventRecordTo = Self.loadSymbol(
            named: "SLPSPostEventRecordTo",
            from: handle
        )
    }

    private static func loadSymbol<Function>(
        named symbolName: String,
        from handle: UnsafeMutableRawPointer?
    ) -> Function? {
        guard let handle, let symbol = dlsym(handle, symbolName) else {
            return nil
        }

        return unsafeBitCast(symbol, to: Function.self)
    }
}
