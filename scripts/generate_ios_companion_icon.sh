#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET_DIR="${ROOT_DIR}/iOS/MudsnoteCompanion/Assets.xcassets/AppIcon.appiconset"
TMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

BASE_ICON="${TMP_DIR}/mudsnote-ios-icon-1024.png"
SWIFT_FILE="${TMP_DIR}/render_mudsnote_ios_icon.swift"

cat > "${SWIFT_FILE}" <<'SWIFT'
import AppKit

let outputPath = CommandLine.arguments[1]
let size = 1024
let bounds = NSRect(x: 0, y: 0, width: size, height: size)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Could not create bitmap representation")
}

rep.size = bounds.size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
NSGraphicsContext.current?.shouldAntialias = true

let background = NSBezierPath(rect: bounds)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.034, green: 0.038, blue: 0.048, alpha: 1),
    NSColor(calibratedRed: 0.080, green: 0.089, blue: 0.110, alpha: 1)
])!
gradient.draw(in: background, angle: 90)

let softHighlight = NSBezierPath(ovalIn: NSRect(x: 118, y: 666, width: 350, height: 230))
NSColor(calibratedRed: 0.90, green: 0.92, blue: 0.96, alpha: 0.055).setFill()
softHighlight.fill()

let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.34)
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.shadowBlurRadius = 34
shadow.set()

let noteRect = NSRect(x: 284, y: 234, width: 456, height: 556)
let note = NSBezierPath(roundedRect: noteRect, xRadius: 72, yRadius: 72)
NSColor(calibratedRed: 0.942, green: 0.936, blue: 0.902, alpha: 1).setFill()
note.fill()

shadow.shadowColor = .clear
shadow.set()

let fold = NSBezierPath()
fold.move(to: NSPoint(x: noteRect.maxX - 132, y: noteRect.maxY))
fold.line(to: NSPoint(x: noteRect.maxX - 36, y: noteRect.maxY))
fold.curve(to: NSPoint(x: noteRect.maxX, y: noteRect.maxY - 96), controlPoint1: NSPoint(x: noteRect.maxX - 8, y: noteRect.maxY), controlPoint2: NSPoint(x: noteRect.maxX, y: noteRect.maxY - 8))
fold.line(to: NSPoint(x: noteRect.maxX, y: noteRect.maxY - 132))
fold.close()
NSColor(calibratedRed: 0.842, green: 0.836, blue: 0.800, alpha: 1).setFill()
fold.fill()

let foldLine = NSBezierPath()
foldLine.move(to: NSPoint(x: noteRect.maxX - 130, y: noteRect.maxY - 2))
foldLine.line(to: NSPoint(x: noteRect.maxX - 2, y: noteRect.maxY - 130))
NSColor(calibratedRed: 0.720, green: 0.714, blue: 0.680, alpha: 0.52).setStroke()
foldLine.lineWidth = 5
foldLine.stroke()

let lineColor = NSColor(calibratedRed: 0.165, green: 0.176, blue: 0.198, alpha: 0.82)
lineColor.setStroke()
for (index, y) in [585.0, 502.0, 419.0].enumerated() {
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 390, y: y))
    line.line(to: NSPoint(x: index == 2 ? 586 : 648, y: y))
    line.lineWidth = 24
    line.lineCapStyle = .round
    line.stroke()
}

let accent = NSBezierPath(roundedRect: NSRect(x: 350, y: 404, width: 26, height: 206), xRadius: 13, yRadius: 13)
NSColor(calibratedRed: 0.271, green: 0.498, blue: 0.922, alpha: 1).setFill()
accent.fill()

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}
try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
SWIFT

swift "${SWIFT_FILE}" "${BASE_ICON}"

resize_png() {
    local size="$1"
    local output="$2"
    sips -z "${size}" "${size}" "${BASE_ICON}" --out "${ICONSET_DIR}/${output}" >/dev/null
}

resize_png 40 "Icon-20@2x.png"
resize_png 60 "Icon-20@3x.png"
resize_png 58 "Icon-29@2x.png"
resize_png 87 "Icon-29@3x.png"
resize_png 80 "Icon-40@2x.png"
resize_png 120 "Icon-40@3x.png"
resize_png 120 "Icon-60@2x.png"
resize_png 180 "Icon-60@3x.png"
resize_png 20 "Icon-20-ipad@1x.png"
resize_png 40 "Icon-20-ipad@2x.png"
resize_png 29 "Icon-29-ipad@1x.png"
resize_png 58 "Icon-29-ipad@2x.png"
resize_png 40 "Icon-40-ipad@1x.png"
resize_png 80 "Icon-40-ipad@2x.png"
resize_png 76 "Icon-76-ipad@1x.png"
resize_png 152 "Icon-76-ipad@2x.png"
resize_png 167 "Icon-83.5-ipad@2x.png"
resize_png 1024 "Icon-1024.png"

echo "Generated iOS companion icon assets in ${ICONSET_DIR}"
