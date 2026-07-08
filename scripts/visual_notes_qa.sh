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

FIXTURE_ROOT="$OUTPUT_DIR/visual-qa-library"
FIXTURE_NOTES_DIR="$FIXTURE_ROOT/Notes"
FIXTURE_APP_SUPPORT_DIR="$FIXTURE_ROOT/AppSupport"
FIXTURE_DEFAULTS_SUITE="local.codex.mudsnote.visual-qa"

rm -rf "$FIXTURE_ROOT"
mkdir -p "$FIXTURE_ROOT"
defaults delete "$FIXTURE_DEFAULTS_SUITE" >/dev/null 2>&1 || true

/usr/bin/swift - "$FIXTURE_NOTES_DIR" "$FIXTURE_APP_SUPPORT_DIR" <<'SWIFT'
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("Usage: seed-visual-qa notes-dir app-support-dir\n", stderr)
    exit(2)
}

let notesDirectory = URL(fileURLWithPath: args[1], isDirectory: true)
let appSupportDirectory = URL(fileURLWithPath: args[2], isDirectory: true)
let trashDirectory = appSupportDirectory.appendingPathComponent("Trash", isDirectory: true)
let fileManager = FileManager.default
try fileManager.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
try fileManager.createDirectory(at: trashDirectory, withIntermediateDirectories: true)

let calendar = Calendar.current
let now = Date()

func fixtureDate(daysAgo: Int, hour: Int, minute: Int) -> Date {
    let shifted = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
    var components = calendar.dateComponents([.year, .month, .day], from: shifted)
    components.hour = hour
    components.minute = minute
    components.second = 0
    return calendar.date(from: components) ?? shifted
}

func noteContent(title: String, body: String) -> String {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedTitle.isEmpty {
        return trimmedBody.isEmpty ? "" : "\(trimmedBody)\n"
    }
    if trimmedBody.isEmpty {
        return "# \(trimmedTitle)\n"
    }
    return "# \(trimmedTitle)\n\n\(trimmedBody)\n"
}

func writeNote(
    directory: URL,
    filename: String,
    title: String,
    body: String,
    daysAgo: Int,
    hour: Int,
    minute: Int
) throws {
    let url = directory.appendingPathComponent(filename)
    try noteContent(title: title, body: body).write(to: url, atomically: true, encoding: .utf8)
    let date = fixtureDate(daysAgo: daysAgo, hour: hour, minute: minute)
    try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
}

try writeNote(
    directory: notesDirectory,
    filename: "New Note.md",
    title: "",
    body: "",
    daysAgo: 0,
    hour: 11,
    minute: 51
)
try writeNote(
    directory: notesDirectory,
    filename: "lz合集.md",
    title: "lz 合集",
    body: "Monday  动机",
    daysAgo: 3,
    hour: 10,
    minute: 15
)
try writeNote(
    directory: notesDirectory,
    filename: "knock 短密码.md",
    title: "knock 短密码",
    body: "135792",
    daysAgo: 5,
    hour: 9,
    minute: 40
)
try writeNote(
    directory: notesDirectory,
    filename: "Call Recording.md",
    title: "Call Recording",
    body: "1 audio recording",
    daysAgo: 21,
    hour: 17,
    minute: 5
)
try writeNote(
    directory: notesDirectory,
    filename: "gptest.md",
    title: "gptest",
    body: "...",
    daysAgo: 250,
    hour: 14,
    minute: 0
)

for index in 1...4 {
    try writeNote(
        directory: trashDirectory,
        filename: "Deleted \(index).md",
        title: "Deleted \(index)",
        body: "",
        daysAgo: 8 + index,
        hour: 8,
        minute: index
    )
}
SWIFT

pkill -x Mudsnote >/dev/null 2>&1 || true
sleep 1
open -n "$APP_PATH" --args \
  --library \
  --visual-qa-defaults-suite "$FIXTURE_DEFAULTS_SUITE" \
  --visual-qa-notes-dir "$FIXTURE_NOTES_DIR" \
  --visual-qa-app-support-dir "$FIXTURE_APP_SUPPORT_DIR"
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

# Keep pointer hover from polluting the static Notes comparison.
/usr/bin/swift - <<'SWIFT'
import CoreGraphics

CGWarpMouseCursorPosition(CGPoint(x: 2, y: 2))
CGAssociateMouseAndMouseCursorPosition(1)
SWIFT
sleep 0.2

APP_SCREENSHOT="$OUTPUT_DIR/mudsnote-library.png"
PAIR_SCREENSHOT="$OUTPUT_DIR/apple-notes-vs-mudsnote.png"
METADATA_PATH="$OUTPUT_DIR/visual-qa-metadata.txt"

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

/usr/bin/swift - "$REFERENCE_PATH" "$APP_SCREENSHOT" "$PAIR_SCREENSHOT" "$METADATA_PATH" "$WINDOW_ID" <<'SWIFT'
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count == 6, let capturedWindowID = Int(args[5]) else {
    fputs("Usage: stitch reference app output metadata window-id\n", stderr)
    exit(2)
}

let referenceURL = URL(fileURLWithPath: args[1])
let appURL = URL(fileURLWithPath: args[2])
let outputURL = URL(fileURLWithPath: args[3])
let metadataURL = URL(fileURLWithPath: args[4])

struct ImageMetrics {
    let url: URL
    let image: NSImage
    let pixelsWide: Int
    let pixelsHigh: Int

    var pointWidth: CGFloat { image.size.width }
    var pointHeight: CGFloat { image.size.height }
    var backingScaleX: CGFloat { CGFloat(pixelsWide) / max(pointWidth, 1) }
    var backingScaleY: CGFloat { CGFloat(pixelsHigh) / max(pointHeight, 1) }
    var backingScaleDescription: String {
        let scale = max(backingScaleX, backingScaleY)
        return String(format: "%.1fx", scale)
    }

    var pointDescription: String {
        "\(Int(pointWidth.rounded()))x\(Int(pointHeight.rounded())) pt"
    }

    var pixelDescription: String {
        "\(pixelsWide)x\(pixelsHigh) px"
    }
}

func capturedWindowBoundsDescription(windowID: Int) -> String {
    let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
    let windows = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
    guard
        let window = windows.first(where: { ($0[kCGWindowNumber as String] as? Int) == windowID }),
        let bounds = window[kCGWindowBounds as String] as? [String: Any],
        let width = bounds["Width"] as? Double,
        let height = bounds["Height"] as? Double,
        let x = bounds["X"] as? Double,
        let y = bounds["Y"] as? Double
    else {
        return "unavailable"
    }
    return String(format: "x=%.0f,y=%.0f,width=%.0f,height=%.0f", x, y, width, height)
}

func loadImageMetrics(_ url: URL) -> ImageMetrics {
    guard
        let image = NSImage(contentsOf: url),
        image.size.width > 0,
        image.size.height > 0,
        let data = try? Data(contentsOf: url),
        let bitmap = NSBitmapImageRep(data: data)
    else {
        fputs("Could not load image: \(url.path)\n", stderr)
        exit(2)
    }
    return ImageMetrics(
        url: url,
        image: image,
        pixelsWide: bitmap.pixelsWide,
        pixelsHigh: bitmap.pixelsHigh
    )
}

func scaledSize(for metrics: ImageMetrics, targetHeight: CGFloat) -> NSSize {
    let ratio = targetHeight / max(metrics.pointHeight, 1)
    return NSSize(width: metrics.pointWidth * ratio, height: targetHeight)
}

func drawLabel(_ title: String, metrics: ImageMetrics, drawScale: CGFloat, in rect: NSRect) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left

    let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.88, alpha: 1),
        .paragraphStyle: paragraph
    ]
    let metricsAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.62, alpha: 1),
        .paragraphStyle: paragraph
    ]

    let text = NSMutableAttributedString(string: "\(title)\n", attributes: titleAttributes)
    let metricsText = "\(metrics.pointDescription) · \(metrics.pixelDescription) · \(metrics.backingScaleDescription) · draw \(String(format: "%.2fx", drawScale))"
    text.append(NSAttributedString(string: metricsText, attributes: metricsAttributes))
    text.draw(in: rect.insetBy(dx: 4, dy: 10))
}

let reference = loadImageMetrics(referenceURL)
let app = loadImageMetrics(appURL)

func imageHasVisibleContent(_ metrics: ImageMetrics) -> Bool {
    guard
        let tiff = metrics.image.tiffRepresentation,
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

let configuredTargetHeight = ProcessInfo.processInfo.environment["MUDSNOTE_VISUAL_QA_TARGET_HEIGHT"].flatMap(Double.init)
let targetHeight = CGFloat(configuredTargetHeight ?? 900)
let labelHeight: CGFloat = 68
let gap: CGFloat = 24
let referenceSize = scaledSize(for: reference, targetHeight: targetHeight)
let appSize = scaledSize(for: app, targetHeight: targetHeight)
let referenceDrawScale = targetHeight / max(reference.pointHeight, 1)
let appDrawScale = targetHeight / max(app.pointHeight, 1)
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
drawLabel(
    "Apple Notes Reference",
    metrics: reference,
    drawScale: referenceDrawScale,
    in: NSRect(x: referenceOrigin.x, y: targetHeight, width: referenceSize.width, height: labelHeight)
)
drawLabel(
    "Mudsnote Current",
    metrics: app,
    drawScale: appDrawScale,
    in: NSRect(x: appOrigin.x, y: targetHeight, width: appSize.width, height: labelHeight)
)
reference.image.draw(in: NSRect(origin: referenceOrigin, size: referenceSize))
app.image.draw(in: NSRect(origin: appOrigin, size: appSize))
canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not render visual QA image\n", stderr)
    exit(2)
}

try png.write(to: outputURL)
let metadata = """
reference_path=\(reference.url.path)
reference_points=\(reference.pointDescription)
reference_pixels=\(reference.pixelDescription)
reference_backing_scale=\(reference.backingScaleDescription)
reference_draw_scale=\(String(format: "%.4f", referenceDrawScale))
mudsnote_path=\(app.url.path)
mudsnote_window_id=\(capturedWindowID)
mudsnote_window_bounds=\(capturedWindowBoundsDescription(windowID: capturedWindowID))
mudsnote_points=\(app.pointDescription)
mudsnote_pixels=\(app.pixelDescription)
mudsnote_backing_scale=\(app.backingScaleDescription)
mudsnote_draw_scale=\(String(format: "%.4f", appDrawScale))
target_height_points=\(Int(targetHeight.rounded()))
comparison_path=\(outputURL.path)
"""
try metadata.write(to: metadataURL, atomically: true, encoding: .utf8)
print(outputURL.path)
SWIFT

{
  echo
  echo "fixture_notes_dir=$FIXTURE_NOTES_DIR"
  echo "fixture_app_support_dir=$FIXTURE_APP_SUPPORT_DIR"
  echo "fixture_defaults_suite=$FIXTURE_DEFAULTS_SUITE"
} >> "$METADATA_PATH"

echo "Reference: $REFERENCE_PATH"
echo "Mudsnote:  $APP_SCREENSHOT"
echo "Compare:   $PAIR_SCREENSHOT"
echo "Metadata:  $METADATA_PATH"
