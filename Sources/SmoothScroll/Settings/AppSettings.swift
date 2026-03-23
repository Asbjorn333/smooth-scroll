@preconcurrency import CoreGraphics
import Foundation

enum TuningLimits {
    static let speed: ClosedRange<Double> = 1.0...1000.0
    static let smoothness: ClosedRange<Double> = 0.0...0.995
    static let decay: ClosedRange<Double> = 0.1...120.0
    static let fps: ClosedRange<Double> = 30.0...360.0
    static let pointerSpeed: ClosedRange<Double> = 0.0...20.0
}

func clampValue(_ value: Double, to range: ClosedRange<Double>) -> Double {
    max(range.lowerBound, min(value, range.upperBound))
}

enum MouseButtonAction: String, CaseIterable {
    case passthrough
    case back
    case forward
    case toggleSmoothScroll
    case keyboardKey

    static let directCases: [MouseButtonAction] = [
        .passthrough,
        .back,
        .forward,
        .toggleSmoothScroll
    ]

    var title: String {
        switch self {
        case .passthrough:
            return "Passthrough"
        case .back:
            return "Back (Cmd+[)"
        case .forward:
            return "Forward (Cmd+])"
        case .toggleSmoothScroll:
            return "Toggle SmoothScroll"
        case .keyboardKey:
            return "Keyboard Key"
        }
    }
}

enum SideMouseButton {
    static let primary: Int64 = 3
    static let secondary: Int64 = 4
}

enum SideMouseButtonSlot: Int {
    case primary = 1
    case secondary = 2

    var title: String {
        switch self {
        case .primary:
            return "Side Button 1 (Button 4)"
        case .secondary:
            return "Side Button 2 (Button 5)"
        }
    }
}

enum MouseButtonKeyboardKey: String, CaseIterable {
    case enter
    case tab
    case space
    case escape
    case deleteBackward
    case deleteForward
    case upArrow
    case downArrow
    case leftArrow
    case rightArrow
    case home
    case end
    case pageUp
    case pageDown

    var title: String {
        switch self {
        case .enter:
            return "Enter"
        case .tab:
            return "Tab"
        case .space:
            return "Space"
        case .escape:
            return "Escape"
        case .deleteBackward:
            return "Delete"
        case .deleteForward:
            return "Forward Delete"
        case .upArrow:
            return "Arrow Up"
        case .downArrow:
            return "Arrow Down"
        case .leftArrow:
            return "Arrow Left"
        case .rightArrow:
            return "Arrow Right"
        case .home:
            return "Home"
        case .end:
            return "End"
        case .pageUp:
            return "Page Up"
        case .pageDown:
            return "Page Down"
        }
    }

    var keyCode: CGKeyCode {
        switch self {
        case .enter:
            return 36
        case .tab:
            return 48
        case .space:
            return 49
        case .escape:
            return 53
        case .deleteBackward:
            return 51
        case .deleteForward:
            return 117
        case .upArrow:
            return 126
        case .downArrow:
            return 125
        case .leftArrow:
            return 123
        case .rightArrow:
            return 124
        case .home:
            return 115
        case .end:
            return 119
        case .pageUp:
            return 116
        case .pageDown:
            return 121
        }
    }

    var flags: CGEventFlags {
        []
    }
}

enum KeyboardKeyCode {
    static let tab: CGKeyCode = 48
    static let escape: CGKeyCode = 53
}

struct EngineSettings {
    var speed: Double
    var smoothness: Double
    var decay: Double
    var fps: Double
    var pointerSpeed: Double
    var sideButtonPrimaryAction: MouseButtonAction
    var sideButtonSecondaryAction: MouseButtonAction
    var sideButtonPrimaryKeyboardKey: MouseButtonKeyboardKey
    var sideButtonSecondaryKeyboardKey: MouseButtonKeyboardKey

    static let `default` = EngineSettings(
        speed: 100.0,
        smoothness: 0.80,
        decay: 28.0,
        fps: 120.0,
        pointerSpeed: PointerSpeedManager.currentSystemValue(),
        sideButtonPrimaryAction: .back,
        sideButtonSecondaryAction: .forward,
        sideButtonPrimaryKeyboardKey: .enter,
        sideButtonSecondaryKeyboardKey: .enter
    )

    var clamped: EngineSettings {
        EngineSettings(
            speed: clampValue(speed, to: TuningLimits.speed),
            smoothness: clampValue(smoothness, to: TuningLimits.smoothness),
            decay: clampValue(decay, to: TuningLimits.decay),
            fps: clampValue(fps, to: TuningLimits.fps),
            pointerSpeed: clampValue(pointerSpeed, to: TuningLimits.pointerSpeed),
            sideButtonPrimaryAction: sideButtonPrimaryAction,
            sideButtonSecondaryAction: sideButtonSecondaryAction,
            sideButtonPrimaryKeyboardKey: sideButtonPrimaryKeyboardKey,
            sideButtonSecondaryKeyboardKey: sideButtonSecondaryKeyboardKey
        )
    }

    func mapping(forMouseButtonNumber buttonNumber: Int64) -> (action: MouseButtonAction, keyboardKey: MouseButtonKeyboardKey) {
        switch buttonNumber {
        case SideMouseButton.primary:
            return (sideButtonPrimaryAction, sideButtonPrimaryKeyboardKey)
        case SideMouseButton.secondary:
            return (sideButtonSecondaryAction, sideButtonSecondaryKeyboardKey)
        default:
            return (.passthrough, .enter)
        }
    }
}
