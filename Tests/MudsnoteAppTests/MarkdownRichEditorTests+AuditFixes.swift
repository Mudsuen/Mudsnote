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

    @Test
    func codecRoundTripsNestedInlineStylesIndentedListsAndDecimalNumbers() {
        // 1.5 should stay a plain paragraph, not become an ordered list item.
        let decimal = MarkdownRichTextCodec.render(markdown: "1.5 版本说明", theme: theme)
        #expect(MarkdownRichTextCodec.serialize(decimal, theme: theme) == "1.5 版本说明")

        // Nested 2-space indented list renders as indented list (not monospace code) and round-trips.
        let nestedList = MarkdownRichTextCodec.render(markdown: "- Parent\n  - Child", theme: theme)
        #expect(MarkdownRichTextCodec.serialize(nestedList, theme: theme) == "- Parent\n  - Child")
        let childIndex = (nestedList.string as NSString).range(of: "Child").location
        let childFont = nestedList.attribute(.font, at: childIndex, effectiveRange: nil) as? NSFont
        #expect(childFont != theme.codeFont)

        // Combined bold+italic round-trips cleanly.
        let combined = MarkdownRichTextCodec.render(markdown: "***BoldItalic*** and **~~BoldStrike~~**", theme: theme)
        #expect(combined.string == "BoldItalic and BoldStrike")
        let serialized = MarkdownRichTextCodec.serialize(combined, theme: theme)
        #expect(serialized.contains("***BoldItalic***"))
        #expect(serialized.contains("~~"))
    }

    @Test
    func quickCaptureDerivedTitlePreservesVersionsNodeJSAndURLs() {
        #expect(QuickCaptureDocumentState.derivedTitle(from: "v1.2.3 发布说明") == "v1.2.3 发布说明")
        #expect(QuickCaptureDocumentState.derivedTitle(from: "Node.js 性能调优") == "Node.js 性能调优")
        #expect(QuickCaptureDocumentState.derivedTitle(from: "https://example.com/docs/guide") == "example.com/docs/guide")
    }

    @Test
    func draftPersistenceCoordinatorPreservesDeleteAfterSaveAndInvokesAllCompletions() async {
        final class Recorder: @unchecked Sendable {
            let lock = NSLock()
            var events: [String] = []
            func record(_ event: String) {
                lock.lock()
                events.append(event)
                lock.unlock()
            }
        }
        let recorder = Recorder()
        let coordinator = DraftPersistenceCoordinator(
            save: { snapshot in
                Thread.sleep(forTimeInterval: 0.02)
                recorder.record("save:\(snapshot.id):\(snapshot.body)")
            },
            delete: { id in
                recorder.record("delete:\(id)")
            }
        )

        var completionCount = 0
        let now = Date()
        coordinator.enqueue(.save(DraftSnapshot(
            id: "d1",
            sourcePath: nil,
            selectedDirectoryPath: "/tmp",
            title: "",
            body: "v1",
            tags: [],
            updatedAt: now
        ))) { _ in completionCount += 1 }
        coordinator.enqueue(.save(DraftSnapshot(
            id: "d1",
            sourcePath: nil,
            selectedDirectoryPath: "/tmp",
            title: "",
            body: "v2",
            tags: [],
            updatedAt: now
        ))) { _ in completionCount += 1 }
        coordinator.enqueue(.delete("d1")) { _ in completionCount += 1 }
        coordinator.waitUntilIdle()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(completionCount == 3)
        #expect(recorder.events.last == "delete:d1")
    }

    @Test
    func quickEntryEditorShortcutDoesNotSwallowSystemCommandQOrW() throws {
        let harness = try makeEditorControllerHarness(draftID: "quick-capture", showsSaveButton: true)
        defer { harness.tearDown() }

        let cmdQ = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: harness.controller.window?.windowNumber ?? 0,
            context: nil,
            characters: "q",
            charactersIgnoringModifiers: "q",
            isARepeat: false,
            keyCode: 12
        ))
        let cmdW = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: harness.controller.window?.windowNumber ?? 0,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        ))
        #expect(harness.controller.handleShortcutEvent(cmdQ) == false)
        #expect(harness.controller.handleShortcutEvent(cmdW) == false)
    }

    @MainActor
    @Test
    func sidebarHeaderTitleStaysLeftAlignedAndFillsSidebarWidth() throws {
        let harness = try makeEditorControllerHarness(draftID: "sidebar-header-layout", showsSaveButton: false)
        defer { harness.tearDown() }

        let controller = LibraryWindowController(
            noteStore: harness.store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showLibraryNavigationPage(.list, scope: .recent)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let sourceContainer = try #require(controller.sourceListView)
        let heading = try #require(controller.sidebarLibraryTitle.superview)
        let titleInContainer = controller.sidebarLibraryTitle.convert(
            controller.sidebarLibraryTitle.bounds,
            to: sourceContainer
        )
        let searchButton = try #require(controller.sidebarSearchButton)
        let searchInContainer = searchButton.convert(searchButton.bounds, to: sourceContainer)

        #expect(abs(heading.frame.width - sourceContainer.bounds.width) < 1)
        #expect(titleInContainer.minX <= 20)
        #expect(searchInContainer.minX > titleInContainer.minX + 60)
    }
}
