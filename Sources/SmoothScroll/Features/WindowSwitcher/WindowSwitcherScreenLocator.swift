@preconcurrency import AppKit
@preconcurrency import CoreGraphics

enum WindowSwitcherScreenLocator {
    private static let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")

    static func screenContainingPointer() -> NSScreen? {
        let pointerLocation = NSEvent.mouseLocation

        if let screen = screen(containing: pointerLocation) {
            return screen
        }

        if let displayID = displayContainingPointer(),
           let screen = screen(forDisplayID: displayID) {
            return screen
        }

        return nearestScreen(to: pointerLocation) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private static func displayContainingPointer() -> CGDirectDisplayID? {
        let point = CGEvent(source: nil)?.location ?? NSEvent.mouseLocation
        var displayID = CGDirectDisplayID()
        var matchCount: UInt32 = 0
        let result = CGGetDisplaysWithPoint(point, 1, &displayID, &matchCount)
        guard result == .success, matchCount > 0 else {
            return nil
        }
        return displayID
    }

    private static func screen(forDisplayID displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let screenNumber = screen.deviceDescription[screenNumberKey] as? NSNumber else {
                return false
            }
            return CGDirectDisplayID(screenNumber.uint32Value) == displayID
        }
    }

    private static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.insetBy(dx: -1, dy: -1).contains(point)
        }
    }

    private static func nearestScreen(to point: NSPoint) -> NSScreen? {
        NSScreen.screens.min { lhs, rhs in
            squaredDistance(from: point, to: lhs.frame) < squaredDistance(from: point, to: rhs.frame)
        }
    }

    private static func squaredDistance(from point: NSPoint, to frame: NSRect) -> CGFloat {
        let dx: CGFloat
        if point.x < frame.minX {
            dx = frame.minX - point.x
        } else if point.x > frame.maxX {
            dx = point.x - frame.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < frame.minY {
            dy = frame.minY - point.y
        } else if point.y > frame.maxY {
            dy = point.y - frame.maxY
        } else {
            dy = 0
        }

        return (dx * dx) + (dy * dy)
    }
}
