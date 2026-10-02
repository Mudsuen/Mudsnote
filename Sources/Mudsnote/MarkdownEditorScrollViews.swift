import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore

final class EditorScrollView: NSScrollView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        if let textView = documentView as? NSTextView {
            window?.makeFirstResponder(textView)
            textView.mouseDown(with: event)
            return
        }

        super.mouseDown(with: event)
    }
}

final class EditorClipView: NSClipView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        if let textView = documentView as? NSTextView {
            window?.makeFirstResponder(textView)
            textView.mouseDown(with: event)
            return
        }

        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRectsOutsideDocumentView()
    }

    override func cursorUpdate(with event: NSEvent) {
        guard !shouldDeferCursorManagement(for: event) else { return }
        NSCursor.iBeam.set()
    }

    override func mouseMoved(with event: NSEvent) {
        guard !shouldDeferCursorManagement(for: event) else {
            super.mouseMoved(with: event)
            return
        }
        NSCursor.iBeam.set()
        super.mouseMoved(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !shouldDeferCursorManagement(for: event) else {
            super.mouseDragged(with: event)
            return
        }
        NSCursor.iBeam.set()
        super.mouseDragged(with: event)
    }

    private func shouldDeferCursorManagement(for event: NSEvent) -> Bool {
        guard let documentView else { return false }
        let point = convert(event.locationInWindow, from: nil)
        return documentView.frame.contains(point)
    }

    private func addCursorRectsOutsideDocumentView() {
        guard let documentView else {
            addCursorRect(bounds, cursor: .iBeam)
            return
        }

        let documentFrame = documentView.frame.intersection(bounds)
        guard !documentFrame.isNull, !documentFrame.isEmpty else {
            addCursorRect(bounds, cursor: .iBeam)
            return
        }

        let topRect = NSRect(
            x: bounds.minX,
            y: documentFrame.maxY,
            width: bounds.width,
            height: max(bounds.maxY - documentFrame.maxY, 0)
        )
        let bottomRect = NSRect(
            x: bounds.minX,
            y: bounds.minY,
            width: bounds.width,
            height: max(documentFrame.minY - bounds.minY, 0)
        )
        let leftRect = NSRect(
            x: bounds.minX,
            y: documentFrame.minY,
            width: max(documentFrame.minX - bounds.minX, 0),
            height: documentFrame.height
        )
        let rightRect = NSRect(
            x: documentFrame.maxX,
            y: documentFrame.minY,
            width: max(bounds.maxX - documentFrame.maxX, 0),
            height: documentFrame.height
        )

        for rect in [topRect, bottomRect, leftRect, rightRect] where rect.width > 0 && rect.height > 0 {
            addCursorRect(rect, cursor: .iBeam)
        }
    }
}
