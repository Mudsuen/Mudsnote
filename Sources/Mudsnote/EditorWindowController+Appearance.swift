import AppKit
import QuartzCore

extension EditorWindowController {

    func prepareRevealAnimation(window: NSWindow) {
        guard let shellContentView else { return }
        window.alphaValue = 0
        shellContentView.alphaValue = 0.01
        shellContentView.layer?.transform = CATransform3DMakeScale(0.985, 0.985, 1)
        window.setFrame(window.frame.offsetBy(dx: 0, dy: -12), display: false)
    }

    func performRevealAnimation(window: NSWindow, targetFrame: NSRect, targetAlpha: CGFloat) {
        guard let shellContentView else {
            window.alphaValue = targetAlpha
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = targetAlpha
            window.animator().setFrame(targetFrame, display: true)
            shellContentView.animator().alphaValue = 1
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        shellContentView.layer?.transform = CATransform3DIdentity
        CATransaction.commit()
    }
}
