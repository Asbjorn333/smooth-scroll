@preconcurrency import ApplicationServices

func requestAccessibilityTrust(prompt: Bool) -> Bool {
    if AXIsProcessTrusted() {
        return true
    }

    guard prompt else {
        return false
    }

    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}
