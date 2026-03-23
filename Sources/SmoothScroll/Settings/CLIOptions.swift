import Foundation

struct CLIOptions {
    var headless = false
    var speed: Double?
    var smoothness: Double?
    var decay: Double?
    var fps: Double?
    var pointerSpeed: Double?

    func applyingOverrides(to settings: EngineSettings) -> EngineSettings {
        var updated = settings
        if let speed { updated.speed = speed }
        if let smoothness { updated.smoothness = smoothness }
        if let decay { updated.decay = decay }
        if let fps { updated.fps = fps }
        if let pointerSpeed { updated.pointerSpeed = pointerSpeed }
        return updated.clamped
    }

    static func parseOrExit() -> CLIOptions {
        var options = CLIOptions()
        var index = 1

        while index < CommandLine.arguments.count {
            let arg = CommandLine.arguments[index]
            switch arg {
            case "--headless":
                options.headless = true
            case "--speed":
                options.speed = parseValue(flag: "--speed", index: &index)
            case "--smoothness":
                options.smoothness = parseValue(flag: "--smoothness", index: &index)
            case "--decay":
                options.decay = parseValue(flag: "--decay", index: &index)
            case "--fps":
                options.fps = parseValue(flag: "--fps", index: &index)
            case "--pointer-speed":
                options.pointerSpeed = parseValue(flag: "--pointer-speed", index: &index)
            case "--help", "-h":
                printUsageAndExit(code: 0)
            default:
                fputs("Unknown argument: \(arg)\n", stderr)
                printUsageAndExit(code: 2)
            }
            index += 1
        }

        return options
    }

    private static func parseValue(flag: String, index: inout Int) -> Double {
        let nextIndex = index + 1
        guard nextIndex < CommandLine.arguments.count,
              let value = Double(CommandLine.arguments[nextIndex]) else {
            fputs("Missing or invalid value for \(flag)\n", stderr)
            printUsageAndExit(code: 2)
        }
        index += 1
        return value
    }

    private static func printUsageAndExit(code: Int32) -> Never {
        let message = """
        SmoothScroll

        Usage:
          SmoothScroll
          SmoothScroll --headless [--speed N] [--smoothness 0..1] [--decay N] [--fps N] [--pointer-speed N]

        Modes:
          (default)      Starts menu bar app with on/off toggle and sliders
          --headless     Starts engine without menu bar UI (terminal mode)

        Options:
          --speed        Scroll strength per wheel notch (\(Int(TuningLimits.speed.lowerBound))..\((Int(TuningLimits.speed.upperBound))), default: \(EngineSettings.default.speed))
          --smoothness   Input blending amount (\(String(format: "%.2f", TuningLimits.smoothness.lowerBound))..\((String(format: "%.3f", TuningLimits.smoothness.upperBound))), default: \(EngineSettings.default.smoothness))
          --decay        Velocity damping per second (\(String(format: "%.1f", TuningLimits.decay.lowerBound))..\((String(format: "%.1f", TuningLimits.decay.upperBound))), default: \(EngineSettings.default.decay))
          --fps          Output event rate in Hz (\(Int(TuningLimits.fps.lowerBound))..\((Int(TuningLimits.fps.upperBound))), default: \(EngineSettings.default.fps))
          --pointer-speed Cursor tracking speed (\(String(format: "%.1f", TuningLimits.pointerSpeed.lowerBound))..\((String(format: "%.1f", TuningLimits.pointerSpeed.upperBound))), default: \(String(format: "%.1f", EngineSettings.default.pointerSpeed)))
        """

        if code == 0 {
            print(message)
        } else {
            fputs(message + "\n", stderr)
        }
        exit(code)
    }
}
