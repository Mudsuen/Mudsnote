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

NSColor(calibratedRed: 0.980, green: 0.980, blue: 0.969, alpha: 1).setFill()
bounds.fill()

NSColor(calibratedRed: 0.067, green: 0.071, blue: 0.078, alpha: 1).setFill()
NSRect(x: 0, y: 724, width: 1024, height: 300).fill()

NSColor(calibratedRed: 0.149, green: 0.153, blue: 0.165, alpha: 1).setFill()
NSRect(x: 0, y: 714, width: 1024, height: 10).fill()

let lineColor = NSColor(calibratedRed: 0.784, green: 0.788, blue: 0.780, alpha: 1)
lineColor.setStroke()
for (index, y) in [600.0, 478.0, 356.0, 234.0, 112.0].enumerated() {
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 128, y: y))
    line.line(to: NSPoint(x: index == 4 ? 720 : 896, y: y))
    line.lineWidth = 15
    line.lineCapStyle = .round
    line.stroke()
}

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
resize_png 1024 "Icon-1024.png"

echo "Generated iOS companion icon assets in ${ICONSET_DIR}"
