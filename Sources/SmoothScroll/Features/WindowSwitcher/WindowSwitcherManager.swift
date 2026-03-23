@preconcurrency import AppKit
@preconcurrency import CoreGraphics
import Foundation

@MainActor
final class WindowSwitcherManager {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var running = false
    private var commandIsDown = false
    private var activeSession: WindowSwitchSession?

    private lazy var overlayController: WindowSwitcherOverlayController = {
        let controller = WindowSwitcherOverlayController()
        controller.onItemActivated = { [weak self] index in
            self?.activateItem(at: index)
        }
        return controller
    }()

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
        commandIsDown = false
        finishSwitching(commitSelection: false)

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
        running
    }

    private func setupEventTap() -> Bool {
        let mask =
            CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.keyUp.rawValue) |
            CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: windowSwitcherTapCallback,
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

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .flagsChanged:
            let isCommandDown = event.flags.contains(.maskCommand)
            let commandWasDown = commandIsDown
            commandIsDown = isCommandDown

            if activeSession != nil, commandWasDown, !isCommandDown {
                finishSwitching(commitSelection: true)
                return nil
            }

            return Unmanaged.passRetained(event)

        case .keyDown:
            if keyCode == KeyboardKeyCode.tab, event.flags.contains(.maskCommand) {
                commandIsDown = true
                cycleSelection(reverse: event.flags.contains(.maskShift))
                return nil
            }

            if activeSession != nil, keyCode == KeyboardKeyCode.escape {
                finishSwitching(commitSelection: false)
                return nil
            }

            return Unmanaged.passRetained(event)

        case .keyUp:
            if activeSession != nil, keyCode == KeyboardKeyCode.tab {
                return nil
            }

            return Unmanaged.passRetained(event)

        default:
            return Unmanaged.passRetained(event)
        }
    }

    private func cycleSelection(reverse: Bool) {
        if var session = activeSession {
            session.selectedIndex = advancedIndex(
                from: session.selectedIndex,
                total: session.windows.count,
                reverse: reverse
            )
            activeSession = session
            presentCurrentSelection()
            return
        }

        let windows = WindowCatalog.visibleWindows()
        guard windows.count > 1 else {
            return
        }

        let initialIndex = reverse ? windows.count - 1 : 1
        let items = windows.map(WindowSnapshotProvider.makeItem(for:))
        activeSession = WindowSwitchSession(items: items, selectedIndex: initialIndex)
        presentCurrentSelection()
    }

    private func presentCurrentSelection() {
        guard let session = activeSession else {
            overlayController.hide()
            return
        }

        overlayController.show(session: session)
    }

    private func finishSwitching(commitSelection: Bool) {
        let selectedWindow = activeSession?.selectedWindow
        activeSession = nil

        overlayController.hide()

        guard commitSelection, let selectedWindow else {
            return
        }

        _ = WindowActivator.activate(selectedWindow)
    }

    private func activateItem(at index: Int) {
        guard var session = activeSession, session.items.indices.contains(index) else {
            return
        }

        session.selectedIndex = index
        activeSession = session
        finishSwitching(commitSelection: true)
    }

    private func advancedIndex(from currentIndex: Int, total: Int, reverse: Bool) -> Int {
        guard total > 0 else {
            return 0
        }

        let delta = reverse ? -1 : 1
        return (currentIndex + delta + total) % total
    }
}

private let windowSwitcherTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passRetained(event)
    }

    let manager = Unmanaged<WindowSwitcherManager>.fromOpaque(userInfo).takeUnretainedValue()
    return MainActor.assumeIsolated {
        manager.handleEvent(type: type, event: event)
    }
}
