import Foundation

final class LaunchAgentManager {
    private let label = "com.smoothscroll.agent"

    private var plistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    @discardableResult
    func enable(executablePath: String) -> Bool {
        guard FileManager.default.fileExists(atPath: executablePath) else {
            return false
        }

        do {
            try FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executablePath],
                "RunAtLoad": true,
                "ProcessType": "Interactive",
                "StandardOutPath": "/tmp/smoothscroll.out.log",
                "StandardErrorPath": "/tmp/smoothscroll.err.log"
            ]

            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        } catch {
            return false
        }

        let domain = "gui/\(getuid())"
        _ = runLaunchctl(["bootout", "\(domain)/\(label)"], ignoreFailure: true)

        guard runLaunchctl(["bootstrap", domain, plistURL.path], ignoreFailure: false) == 0 else {
            return false
        }

        _ = runLaunchctl(["enable", "\(domain)/\(label)"], ignoreFailure: true)
        _ = runLaunchctl(["kickstart", "-k", "\(domain)/\(label)"], ignoreFailure: true)
        return true
    }

    @discardableResult
    func disable() -> Bool {
        let domain = "gui/\(getuid())"
        _ = runLaunchctl(["bootout", "\(domain)/\(label)"], ignoreFailure: true)

        do {
            if FileManager.default.fileExists(atPath: plistURL.path) {
                try FileManager.default.removeItem(at: plistURL)
            }
            return true
        } catch {
            return false
        }
    }

    private func runLaunchctl(_ arguments: [String], ignoreFailure: Bool) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            if !ignoreFailure, process.terminationStatus != 0 {
                return process.terminationStatus
            }
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
