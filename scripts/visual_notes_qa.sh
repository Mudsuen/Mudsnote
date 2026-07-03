#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${MUDSNOTE_APP_PATH:-/Applications/Mudsnote.app}"
REFERENCE_PATH="${MUDSNOTE_NOTES_REFERENCE:-$ROOT_DIR/docs/visual-qa/apple-notes-reference.png}"
OUTPUT_DIR="${1:-/tmp/mudsnote-visual-qa}"

mkdir -p "$OUTPUT_DIR"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing app bundle: $APP_PATH" >&2
  exit 1
fi

if [[ ! -f "$REFERENCE_PATH" ]]; then
  echo "Missing Apple Notes reference image: $REFERENCE_PATH" >&2
  exit 1
fi

pkill -x Mudsnote >/dev/null 2>&1 || true
sleep 1
open -n "$APP_PATH" --args --library
osascript -e 'tell application "Mudsnote" to activate' >/dev/null 2>&1 || true
sleep "${MUDSNOTE_VISUAL_QA_LAUNCH_DELAY:-4}"
osascript -e 'tell application "Mudsnote" to activate' >/dev/null 2>&1 || true

WINDOW_ID="$(/usr/bin/swift - <<'SWIFT'
import CoreGraphics

let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
let windows = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []

struct Candidate {
    let id: Int
    let isLibrary: Bool
    let area: Double
}

let candidates = windows.compactMap { window -> Candidate? in
    guard (window[kCGWindowOwnerName as String] as? String) == "Mudsnote",
          let id = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double,
          width >= 600,
          height >= 400
    else {
        return nil
    }
    let name = window[kCGWindowName as String] as? String ?? ""
    return Candidate(id: id, isLibrary: name.contains("笔记") || name.localizedCaseInsensitiveContains("notes"), area: width * height)
}

if let best = candidates.sorted(by: {
    if $0.isLibrary != $1.isLibrary { return $0.isLibrary && !$1.isLibrary }
    return $0.area > $1.area
}).first {
    print(best.id)
}
SWIFT
)"

if [[ -z "$WINDOW_ID" ]]; then
  echo "Could not find an on-screen Mudsnote library window." >&2
  exit 1
fi

APP_SCREENSHOT="$OUTPUT_DIR/mudsnote-library.png"
PAIR_SCREENSHOT="$OUTPUT_DIR/apple-notes-vs-mudsnote.png"

if ! screencapture -x -l "$WINDOW_ID" "$APP_SCREENSHOT" 2>/dev/null; then
  echo "Window capture unavailable; falling back to full-screen crop." >&2
  FULL_SCREENSHOT="$OUTPUT_DIR/mudsnote-fullscreen.png"
  screencapture -x "$FULL_SCREENSHOT"
  /usr/bin/swift - "$WINDOW_ID" "$FULL_SCREENSHOT" "$APP_SCREENSHOT" <<'SWIFT'
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count == 4, let targetWindowID = Int(args[1]) else {
    fputs("Usage: crop-window window-id full output\n", stderr)
    exit(2)
}

let fullURL = URL(fileURLWithPath: args[2])
let outputURL = URL(fileURLWithPath: args[3])
let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
let windows = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []

guard
    let window = windows.first(where: { ($0[kCGWindowNumber as String] as? Int) == targetWindowID }),
    let bounds = window[kCGWindowBounds as String] as? [String: Any],
    let x = bounds["X"] as? Double,
    let y = bounds["Y"] as? Double,
    let width = bounds["Width"] as? Double,
    let height = bounds["Height"] as? Double,
    let fullData = try? Data(contentsOf: fullURL),
    let source = NSBitmapImageRep(data: fullData),
    let cgImage = source.cgImage
else {
    fputs("Could not crop Mudsnote window from full screenshot\n", stderr)
    exit(2)
}

let screenFrame = NSScreen.screens.reduce(CGRect.null) { partial, screen in
    partial.union(screen.frame)
}
let scaleX = CGFloat(source.pixelsWide) / max(screenFrame.width, 1)
let scaleY = CGFloat(source.pixelsHigh) / max(screenFrame.height, 1)
let cropRect = CGRect(
    x: CGFloat(x) * scaleX,
    y: CGFloat(y) * scaleY,
    width: CGFloat(width) * scaleX,
    height: CGFloat(height) * scaleY
).integral.intersection(CGRect(x: 0, y: 0, width: source.pixelsWide, height: source.pixelsHigh))

guard let cropped = cgImage.cropping(to: cropRect), cropRect.width > 0, cropRect.height > 0 else {
    fputs("Could not create cropped Mudsnote window image\n", stderr)
    exit(2)
}

let bitmap = NSBitmapImageRep(cgImage: cropped)
guard let png = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
    fputs("Could not encode cropped Mudsnote window image\n", stderr)
    exit(2)
}
try png.write(to: outputURL)
SWIFT
fi

/usr/bin/swift - "$REFERENCE_PATH" "$APP_SCREENSHOT" "$PAIR_SCREENSHOT" <<'SWIFT'
import AppKit

let args = CommandLine.arguments
guard args.count == 4 else {
    fputs("Usage: stitch reference app output\n", stderr)
    exit(2)
}

let referenceURL = URL(fileURLWithPath: args[1])
let appURL = URL(fileURLWithPath: args[2])
let outputURL = URL(fileURLWithPath: args[3])

func loadImage(_ url: URL) -> NSImage {
    guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
        fputs("Could not load image: \(url.path)\n", stderr)
        exit(2)
    }
    return image
}

func scaledSize(for image: NSImage, targetHeight: CGFloat) -> NSSize {
    let ratio = targetHeight / max(image.size.height, 1)
    return NSSize(width: image.size.width * ratio, height: targetHeight)
}

func drawLabel(_ text: String, in rect: NSRect) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.88, alpha: 1),
        .paragraphStyle: paragraph
    ]
    text.draw(in: rect.insetBy(dx: 4, dy: 12), withAttributes: attributes)
}

let reference = loadImage(referenceURL)
let app = loadImage(appURL)

func imageHasVisibleContent(_ image: NSImage) -> Bool {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff)
    else {
        return false
    }

    let stepX = max(bitmap.pixelsWide / 80, 1)
    let stepY = max(bitmap.pixelsHigh / 80, 1)
    var brightSamples = 0
    var totalSamples = 0

    for y in stride(from: 0, to: bitmap.pixelsHigh, by: stepY) {
        for x in stride(from: 0, to: bitmap.pixelsWide, by: stepX) {
            guard let color = bitmap.colorAt(x: x, y: y) else { continue }
            totalSamples += 1
            let brightness = max(color.redComponent, color.greenComponent, color.blueComponent)
            if color.alphaComponent > 0.05 && brightness > 0.08 {
                brightSamples += 1
            }
        }
    }

    return totalSamples > 0 && Double(brightSamples) / Double(totalSamples) > 0.002
}

guard imageHasVisibleContent(app) else {
    fputs("Mudsnote screenshot appears blank; check macOS screen capture permissions or the active desktop session.\n", stderr)
    exit(2)
}

let targetHeight: CGFloat = 900
let labelHeight: CGFloat = 52
let gap: CGFloat = 24
let referenceSize = scaledSize(for: reference, targetHeight: targetHeight)
let appSize = scaledSize(for: app, targetHeight: targetHeight)
let canvasSize = NSSize(
    width: referenceSize.width + gap + appSize.width,
    height: labelHeight + targetHeight
)

let canvas = NSImage(size: canvasSize)
canvas.lockFocus()
NSColor(calibratedWhite: 0.075, alpha: 1).setFill()
NSRect(origin: .zero, size: canvasSize).fill()

let referenceOrigin = NSPoint(x: 0, y: 0)
let appOrigin = NSPoint(x: referenceSize.width + gap, y: 0)
drawLabel("Apple Notes Reference", in: NSRect(x: referenceOrigin.x, y: targetHeight, width: referenceSize.width, height: labelHeight))
drawLabel("Mudsnote Current", in: NSRect(x: appOrigin.x, y: targetHeight, width: appSize.width, height: labelHeight))
reference.draw(in: NSRect(origin: referenceOrigin, size: referenceSize))
app.draw(in: NSRect(origin: appOrigin, size: appSize))
canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not render visual QA image\n", stderr)
    exit(2)
}

try png.write(to: outputURL)
print(outputURL.path)
SWIFT

echo "Reference: $REFERENCE_PATH"
echo "Mudsnote:  $APP_SCREENSHOT"
echo "Compare:   $PAIR_SCREENSHOT"
