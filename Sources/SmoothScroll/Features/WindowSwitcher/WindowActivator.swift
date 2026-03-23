@preconcurrency import AppKit
@preconcurrency import ApplicationServices

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
