@preconcurrency import CoreGraphics
import Foundation

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

            let boundsDictionary = windowInfo[kCGWindowBounds as String] as? [String: Any]
            let bounds = boundsDictionary.flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero
            let width = bounds.width
            let height = bounds.height
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
                    windowTitle: title,
                    bounds: bounds
                )
            )
        }

        return windows
    }
}
