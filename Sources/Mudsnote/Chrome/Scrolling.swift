import AppKit
import QuartzCore

@MainActor
final class SlimScroller: NSScroller {
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        8
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        let trackRect = slotRect
        NSColor.black.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: 4, yRadius: 4).fill()
    }

    override func drawKnob() {
        var knobRect = rect(for: .knob)
        guard !knobRect.isEmpty else { return }
        knobRect = knobRect.insetBy(dx: 0, dy: 1)
        NSColor.black.withAlphaComponent(0.34).setFill()
        NSBezierPath(roundedRect: knobRect, xRadius: 3, yRadius: 3).fill()
    }
}

@MainActor
final class ScrollIndicatorOverlay: NSView {
    private weak var scrollView: NSScrollView?
    private let trackLayer = CALayer()
    private let knobLayer = CALayer()
    private var dragOffsetY: CGFloat = 0
    private var isDraggingKnob = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false
        trackLayer.backgroundColor = NSColor.black.withAlphaComponent(0.14).cgColor
        knobLayer.backgroundColor = NSColor.black.withAlphaComponent(0.32).cgColor
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(knobLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateIndicator()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func attach(to scrollView: NSScrollView) {
        self.scrollView = scrollView
        updateIndicator()
    }

    func updateIndicator() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let scrollView, let documentView = scrollView.documentView else {
            isHidden = true
            return
        }

        let visibleRect = scrollView.contentView.documentVisibleRect
        let documentHeight = max(documentView.bounds.height, 1)
        let visibleHeight = visibleRect.height
        let needsScroll = documentHeight > (visibleHeight + 1)
        isHidden = !needsScroll

        guard needsScroll else { return }

        trackLayer.frame = bounds
        trackLayer.cornerRadius = bounds.width / 2

        let knobHeight = max((visibleHeight / documentHeight) * bounds.height, 40)
        let availableTravel = max(bounds.height - knobHeight, 0)
        let maxOffset = max(documentHeight - visibleHeight, 1)
        let progress = min(max(visibleRect.minY / maxOffset, 0), 1)
        knobLayer.frame = CGRect(x: 0, y: progress * availableTravel, width: bounds.width, height: knobHeight)
        knobLayer.cornerRadius = bounds.width / 2
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if knobLayer.frame.contains(point) {
            isDraggingKnob = true
            dragOffsetY = point.y - knobLayer.frame.minY
            return
        }

        jumpKnob(to: point.y)
        isDraggingKnob = true
        dragOffsetY = knobLayer.frame.height / 2
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggingKnob else { return }
        let point = convert(event.locationInWindow, from: nil)
        scroll(toKnobOriginY: point.y - dragOffsetY)
    }

    override func mouseUp(with event: NSEvent) {
        isDraggingKnob = false
    }

    private func jumpKnob(to y: CGFloat) {
        scroll(toKnobOriginY: y - (knobLayer.frame.height / 2))
    }

    private func scroll(toKnobOriginY proposedOriginY: CGFloat) {
        guard let scrollView, let documentView = scrollView.documentView else { return }

        let knobHeight = knobLayer.frame.height
        let availableTravel = max(bounds.height - knobHeight, 0)
        let knobOriginY = min(max(proposedOriginY, 0), availableTravel)
        let maxOffset = max(documentView.bounds.height - scrollView.contentView.documentVisibleRect.height, 0)
        let progress = availableTravel > 0 ? (knobOriginY / availableTravel) : 0
        let targetY = progress * maxOffset
        scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateIndicator()
    }
}
