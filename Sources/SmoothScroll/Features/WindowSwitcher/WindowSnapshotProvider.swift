@preconcurrency import AppKit
@preconcurrency import CoreGraphics

enum WindowSnapshotProvider {
    private static let maximumPreviewSize = NSSize(width: 360, height: 220)

    static func makeItem(for target: WindowSwitchTarget) -> WindowSwitchItem {
        let appIcon = NSRunningApplication(processIdentifier: target.processID)?.icon
        return WindowSwitchItem(
            target: target,
            appIcon: appIcon,
            previewImage: capturePreview(for: target)
        )
    }

    private static func capturePreview(for target: WindowSwitchTarget) -> NSImage? {
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            target.windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }

        let originalSize = NSSize(width: cgImage.width, height: cgImage.height)
        let fittedSize = aspectFitSize(originalSize, within: maximumPreviewSize)
        let sourceImage = NSImage(cgImage: cgImage, size: originalSize)
        let image = NSImage(size: fittedSize)

        image.lockFocus()
        if let context = NSGraphicsContext.current {
            context.imageInterpolation = .high
        }
        sourceImage.draw(
            in: NSRect(origin: .zero, size: fittedSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1
        )
        image.unlockFocus()

        return image
    }

    private static func aspectFitSize(_ size: NSSize, within maxSize: NSSize) -> NSSize {
        guard size.width > 0, size.height > 0 else {
            return maxSize
        }

        let widthScale = maxSize.width / size.width
        let heightScale = maxSize.height / size.height
        let scale = min(widthScale, heightScale, 1.0)

        return NSSize(
            width: max(1, floor(size.width * scale)),
            height: max(1, floor(size.height * scale))
        )
    }
}
