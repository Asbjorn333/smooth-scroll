#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_ICNS="${1:-$ROOT_DIR/dist/AppIcon.icns}"

WORK_DIR="$(mktemp -d "$ROOT_DIR/.iconwork.XXXXXX")"
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"
SOURCE_PNG="$WORK_DIR/source-1024.png"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$ICONSET_DIR"
mkdir -p "$(dirname "$OUT_ICNS")"

swift - "$SOURCE_PNG" <<'SWIFT'
import AppKit
import Foundation

let outputPath = CommandLine.arguments[1]
let size: CGFloat = 1024
let rect = NSRect(x: 0, y: 0, width: size, height: size)

let image = NSImage(size: rect.size)
image.lockFocus()

if let context = NSGraphicsContext.current?.cgContext {
    context.saveGState()

    // Background gradient
    let bgGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(calibratedRed: 0.07, green: 0.11, blue: 0.18, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.10, green: 0.21, blue: 0.35, alpha: 1.0).cgColor
        ] as CFArray,
        locations: [0.0, 1.0]
    )!

    let roundedPath = NSBezierPath(roundedRect: rect.insetBy(dx: 40, dy: 40), xRadius: 230, yRadius: 230)
    context.addPath(roundedPath.cgPath)
    context.clip()
    context.drawLinearGradient(
        bgGradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: []
    )
    context.resetClip()

    // Inner glow
    let glowRect = rect.insetBy(dx: 190, dy: 190)
    let glowPath = NSBezierPath(ovalIn: glowRect)
    context.setFillColor(NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor)
    context.addPath(glowPath.cgPath)
    context.fillPath()

    // Up/down arrows
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
    context.setLineWidth(70)
    context.setLineCap(.round)

    // Main vertical stem
    context.move(to: CGPoint(x: size * 0.5, y: size * 0.26))
    context.addLine(to: CGPoint(x: size * 0.5, y: size * 0.74))
    context.strokePath()

    // Up arrow head
    context.move(to: CGPoint(x: size * 0.40, y: size * 0.64))
    context.addLine(to: CGPoint(x: size * 0.5, y: size * 0.78))
    context.addLine(to: CGPoint(x: size * 0.60, y: size * 0.64))
    context.strokePath()

    // Down arrow head
    context.move(to: CGPoint(x: size * 0.40, y: size * 0.36))
    context.addLine(to: CGPoint(x: size * 0.5, y: size * 0.22))
    context.addLine(to: CGPoint(x: size * 0.60, y: size * 0.36))
    context.strokePath()

    context.restoreGState()
}

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to render icon image\n", stderr)
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
} catch {
    fputs("Failed to write icon PNG: \(error)\n", stderr)
    exit(1)
}
SWIFT

# Standard macOS iconset sizes.
sips -z 16 16 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$SOURCE_PNG" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$OUT_ICNS"

echo "Generated icon: $OUT_ICNS"
