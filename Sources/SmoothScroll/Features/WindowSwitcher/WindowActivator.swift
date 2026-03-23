@preconcurrency import AppKit
@preconcurrency import ApplicationServices

enum WindowActivator {
    @discardableResult
    static func activate(_ target: WindowSwitchTarget) -> Bool {
        let runningApplication = NSRunningApplication(processIdentifier: target.processID)
        let applicationElement = AXUIElementCreateApplication(target.processID)
        let windows = copyWindowElements(from: applicationElement)

        if let matchingWindow = matchingWindow(for: target, in: windows) {
            runningApplication?.activate(options: [.activateIgnoringOtherApps])
            return focus(window: matchingWindow, in: applicationElement)
        }

        guard let runningApplication else {
            return false
        }

        return runningApplication.activate(options: [.activateIgnoringOtherApps])
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

    private static func matchingWindow(for target: WindowSwitchTarget, in windows: [AXUIElement]) -> AXUIElement? {
        var bestWindow: AXUIElement?
        var bestScore = Int.min

        for window in windows {
            let score = matchScore(for: window, target: target)
            guard score > bestScore else {
                continue
            }

            bestScore = score
            bestWindow = window
        }

        return bestScore > 0 ? bestWindow : nil
    }

    private static func matchScore(for window: AXUIElement, target: WindowSwitchTarget) -> Int {
        if windowNumber(for: window) == target.windowID {
            return 10_000
        }

        var score = 0

        if !target.bounds.isEmpty, let frame = frame(for: window) {
            if roughlyMatches(frame, target.bounds, tolerance: 2) {
                score += 1_000
            } else if roughlyMatches(frame, target.bounds, tolerance: 6) {
                score += 700
            }
        }

        if !target.windowTitle.isEmpty, title(for: window) == target.windowTitle {
            score += 300
        }

        return score
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

    private static func frame(for window: AXUIElement) -> CGRect? {
        guard let position = position(for: window),
              let size = size(for: window) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private static func position(for window: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard
              AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var position = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &position) else {
            return nil
        }

        return position
    }

    private static func size(for window: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard
              AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private static func roughlyMatches(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 6) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
            abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
            abs(lhs.size.width - rhs.size.width) <= tolerance &&
            abs(lhs.size.height - rhs.size.height) <= tolerance
    }

    @discardableResult
    private static func focus(window: AXUIElement, in applicationElement: AXUIElement) -> Bool {
        let frontmostResult = AXUIElementSetAttributeValue(
            applicationElement,
            kAXFrontmostAttribute as CFString,
            kCFBooleanTrue
        )
        let mainWindowResult = AXUIElementSetAttributeValue(
            applicationElement,
            kAXMainWindowAttribute as CFString,
            window
        )
        let focusedWindowResult = AXUIElementSetAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            window
        )
        let raiseResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        let mainResult = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        let focusedResult = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)

        let results = [frontmostResult, mainWindowResult, focusedWindowResult, raiseResult, mainResult, focusedResult]
        return results.contains(.success)
    }
}
