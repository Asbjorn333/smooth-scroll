@preconcurrency import AppKit
@preconcurrency import CoreGraphics

struct WindowSwitchTarget {
    let windowID: CGWindowID
    let processID: pid_t
    let appName: String
    let windowTitle: String

    var displayTitle: String {
        windowTitle.isEmpty ? appName : windowTitle
    }

    var detailTitle: String {
        windowTitle.isEmpty ? "Application Window" : appName
    }
}

struct WindowSwitchItem {
    let target: WindowSwitchTarget
    let appIcon: NSImage?
    let previewImage: NSImage?
}

struct WindowSwitchSession {
    let items: [WindowSwitchItem]
    var selectedIndex: Int

    var windows: [WindowSwitchTarget] {
        items.map(\.target)
    }

    var selectedItem: WindowSwitchItem {
        items[selectedIndex]
    }

    var selectedWindow: WindowSwitchTarget {
        selectedItem.target
    }
}
