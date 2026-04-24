import AppKit
import MudsnoteCore

@MainActor
func clampedPanelOpacity(_ rawOpacity: Double) -> CGFloat {
    min(max(CGFloat(rawOpacity), CGFloat(NoteStore.minimumPanelOpacity)), CGFloat(NoteStore.maximumPanelOpacity))
}

@MainActor
func normalizedPanelOpacity(_ rawOpacity: Double) -> CGFloat {
    let clamped = clampedPanelOpacity(rawOpacity)
    let lower = CGFloat(NoteStore.minimumPanelOpacity)
    let upper = CGFloat(NoteStore.maximumPanelOpacity)
    let span = max(upper - lower, 0.01)
    return (clamped - lower) / span
}

@MainActor
func accentSurfaceAlpha(for rawOpacity: Double) -> CGFloat {
    0.84 + (normalizedPanelOpacity(rawOpacity) * 0.10)
}

@MainActor
func primarySurfaceAlpha(for rawOpacity: Double) -> CGFloat {
    0.80 + (normalizedPanelOpacity(rawOpacity) * 0.12)
}

@MainActor
func secondarySurfaceAlpha(for rawOpacity: Double) -> CGFloat {
    0.76 + (normalizedPanelOpacity(rawOpacity) * 0.10)
}

@MainActor
func windowAlphaValue(for rawOpacity: Double) -> CGFloat {
    0.84 + (normalizedPanelOpacity(rawOpacity) * 0.12)
}

@MainActor
protocol WindowOpacityAdjusting: AnyObject {
    func updatePanelOpacity(_ opacity: Double)
}
