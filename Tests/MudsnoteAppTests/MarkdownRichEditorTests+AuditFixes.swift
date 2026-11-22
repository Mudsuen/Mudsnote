import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Mudsnote
@testable import MudsnoteCore

extension MarkdownRichEditorTests {
    @MainActor
    @Test
    func markdownTextViewDoesNotStealUndoFromFocusedSiblingField() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let contentView = try #require(window.contentView)
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let searchField = NSTextField(frame: NSRect(x: 0, y: 220, width: 200, height: 24))
        contentView.addSubview(textView)
        contentView.addSubview(searchField)

        window.makeFirstResponder(textView)
        textView.insertText("Original body", replacementRange: NSRange(location: 0, length: 0))
        #expect(textView.string == "Original body")

        window.makeFirstResponder(searchField)
        let undoEvent = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "z",
            charactersIgnoringModifiers: "z",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_Z)
        ))
        #expect(!textView.performKeyEquivalent(with: undoEvent))
        #expect(textView.string == "Original body")
    }

    @MainActor
    @Test
    func floatingNoteSwitchResetsActiveTagsToTargetNote() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }

        let noteA = try harness.store.saveNewNote(title: "Note A", body: "Body A", tags: ["alpha"])
        let noteB = try harness.store.saveNewNote(title: "Note B", body: "Body B", tags: ["beta"])

        harness.controller.loadFloatingNote(at: noteA)
        #expect(harness.controller.currentDocument().tags == ["alpha"])

        harness.controller.loadFloatingNote(at: noteB)
        #expect(harness.controller.currentDocument().tags == ["beta"])
    }

    @MainActor
    @Test
    func libraryWindowTracksExplicitClosedStateSeparatelyFromVisibility() throws {
        let harness = try makeEditorControllerHarness(draftID: "library-close-state", showsSaveButton: false)
        defer { harness.tearDown() }

        let controller = LibraryWindowController(
            noteStore: harness.store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        #expect(!controller.isWindowClosed)
        controller.window?.orderOut(nil)
        #expect(!controller.isWindowClosed)
        controller.close()
        #expect(controller.isWindowClosed)
    }

    @MainActor
    @Test
    func portraitEXIFImagePixelSizeSwapsDimensions() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-exif-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURL = tempDir.appendingPathComponent("portrait.jpg")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: 40,
            height: 20,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let cgImage = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(
            imageURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, cgImage, [
            kCGImagePropertyOrientation: 6
        ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))

        let size = try #require(MarkdownImageDecoding.pixelSize(at: imageURL))
        #expect(size == NSSize(width: 20, height: 40))
    }
}
