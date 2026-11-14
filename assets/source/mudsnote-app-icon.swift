#!/usr/bin/env swift
import AppKit

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift mudsnote-app-icon.swift <output.png>")
}
let size = 1024
let bounds = NSRect(x: 0, y: 0, width: size, height: size)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = bounds.size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.shouldAntialias = true
NSColor.clear.setFill()
bounds.fill()
let background = NSColor(calibratedRed: 0.031, green: 0.035, blue: 0.039, alpha: 1)
let foreground = NSColor(calibratedRed: 0.965, green: 0.965, blue: 0.953, alpha: 1)
background.setFill()
NSBezierPath(roundedRect: NSRect(x: 74, y: 74, width: 876, height: 876),
    xRadius: 206, yRadius: 206).fill()

// One page and three lines: a note, legible without a letter or a miniature UI.
foreground.setStroke()
let page = NSBezierPath(roundedRect: NSRect(x: 326, y: 270, width: 372, height: 484),
    xRadius: 40, yRadius: 40)
page.lineWidth = 44
page.stroke()
for (y, end) in [(604.0, 606.0), (500.0, 606.0), (396.0, 556.0)] {
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 418, y: y))
    line.line(to: NSPoint(x: end, y: y))
    line.lineWidth = 40
    line.lineCapStyle = .round
    line.stroke()
}

NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(
    to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
