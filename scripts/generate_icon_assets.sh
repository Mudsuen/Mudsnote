#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="${ROOT_DIR}/assets/source"
GENERATED_DIR="${ROOT_DIR}/assets/generated"
TMP_DIR="$(mktemp -d)"
ICONSET_DIR="${GENERATED_DIR}/MudsnoteAppIcon.iconset"

cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

render_svg() {
    local svg_path="$1"
    local size="$2"
    qlmanage -t -s "${size}" -o "${TMP_DIR}" "${svg_path}" >/dev/null 2>&1
    find "${TMP_DIR}" -maxdepth 1 -type f -name "$(basename "${svg_path}")*.png" | head -n 1
}

render_app_icon_png() {
    local output_png="$1"
    local swift_file="${TMP_DIR}/render_mudsnote_app_icon.swift"
    cat > "${swift_file}" <<'SWIFT'
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

NSColor.clear.setFill()
bounds.fill()

let basePath = NSBezierPath(roundedRect: NSRect(x: 74, y: 74, width: 876, height: 876), xRadius: 206, yRadius: 206)
NSColor(calibratedRed: 0.031, green: 0.035, blue: 0.039, alpha: 1).setFill()
basePath.fill()

let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.38)
shadow.shadowOffset = NSSize(width: 0, height: -16)
shadow.shadowBlurRadius = 30
shadow.set()

let cardRect = NSRect(x: 315, y: 278, width: 394, height: 450)
let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 50, yRadius: 50)
NSColor(calibratedRed: 0.965, green: 0.965, blue: 0.953, alpha: 1).setFill()
cardPath.fill()

shadow.shadowColor = .clear
shadow.set()

NSColor(calibratedRed: 0.976, green: 0.976, blue: 0.965, alpha: 1).setFill()
cardPath.fill()

let lineColor = NSColor(calibratedRed: 0.725, green: 0.725, blue: 0.714, alpha: 1)
lineColor.setStroke()
for y in [392.0, 472.0, 552.0, 632.0] {
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 410, y: y))
    line.line(to: NSPoint(x: 614, y: y))
    line.lineWidth = 18
    line.lineCapStyle = .round
    line.stroke()
}

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}
try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
SWIFT
    swift "${swift_file}" "${output_png}"
}

resize_png() {
    local input_png="$1"
    local size="$2"
    local output_png="$3"
    sips -z "${size}" "${size}" "${input_png}" --out "${output_png}" >/dev/null
}

mkdir -p "${GENERATED_DIR}"
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

APP_SVG="${SOURCE_DIR}/mudsnote-app-icon.svg"
STATUS_SVG="${SOURCE_DIR}/mudsnote-status-template.svg"

BASE_ICON_PNG="${TMP_DIR}/MudsnoteAppIcon-base.png"
render_app_icon_png "${BASE_ICON_PNG}"
if [[ -z "${BASE_ICON_PNG}" || ! -f "${BASE_ICON_PNG}" ]]; then
    echo "Failed to render app icon SVG" >&2
    exit 1
fi

for spec in \
    "16:icon_16x16.png" \
    "32:icon_16x16@2x.png" \
    "32:icon_32x32.png" \
    "64:icon_32x32@2x.png" \
    "128:icon_128x128.png" \
    "256:icon_128x128@2x.png" \
    "256:icon_256x256.png" \
    "512:icon_256x256@2x.png" \
    "512:icon_512x512.png" \
    "1024:icon_512x512@2x.png"; do
    size="${spec%%:*}"
    name="${spec#*:}"
    resize_png "${BASE_ICON_PNG}" "${size}" "${ICONSET_DIR}/${name}"
done

rm -f "${GENERATED_DIR}/MudsnoteAppIcon.icns"
iconutil -c icns "${ICONSET_DIR}" -o "${GENERATED_DIR}/MudsnoteAppIcon.icns"

BASE_STATUS_PNG="$(render_svg "${STATUS_SVG}" 64)"
if [[ -z "${BASE_STATUS_PNG}" || ! -f "${BASE_STATUS_PNG}" ]]; then
    echo "Failed to render status icon SVG" >&2
    exit 1
fi

resize_png "${BASE_STATUS_PNG}" 36 "${GENERATED_DIR}/MudsnoteStatusTemplate.png"
