import AppKit
import MudsnoteCore

enum LibraryNotesLayout {
    static let storedLayoutScaleVersion = 8
    static let initialWindowSize = NSSize(width: 921, height: 613)
    static let presentedWindowSize = NSSize(width: 921, height: 613)
    static let minimumWindowSize = NSSize(width: 896, height: 560)
    static let previousDefaultWindowSizes = [
        NSSize(width: 940, height: 630),
        NSSize(width: 1080, height: 680),
        NSSize(width: 1080, height: 720)
    ]
    static let sourceColumnWidth: CGFloat = 200
    static let noteColumnWidth: CGFloat = 200
    static let sourceColumnMinimumWidth: CGFloat = 200
    static let sourceColumnMaximumWidth: CGFloat = 320
    static let noteColumnMinimumWidth: CGFloat = 200
    static let noteColumnMaximumWidth: CGFloat = 320
    static let editorColumnMinimumWidth: CGFloat = 480
    static let noteTableInitialWidth: CGFloat = 174
    static let noteTableMinimumWidth: CGFloat = 174
    static let toolbarSearchWidth: CGFloat = 160
    static let toolbarSearchHeight: CGFloat = 32
    static let toolbarSearchWrapperWidth: CGFloat = 160
    static let toolbarSearchWrapperHeight: CGFloat = 36
    static let toolbarEditorToolsWidth: CGFloat = 155
    static let toolbarEditorToolsSlotWidth: CGFloat = 162
    static let toolbarEditorToolsHeight: CGFloat = 32
    static let toolbarEditorToolButtonWidth: CGFloat = 31
    static let toolbarEditorToolButtonHeight: CGFloat = 26
    static let toolbarEditorToolSymbolPointSize: CGFloat = 13
    static let toolbarEditorFormatFontSize: CGFloat = 17
    static let toolbarCircularButtonSize: CGFloat = 30
    static let toolbarNewNoteWrapperWidth: CGFloat = 44
    static let toolbarCollapsedSidebarWrapperWidth: CGFloat = 34
    static let toolbarExpandedTitleLeadingOffset: CGFloat = 12
    static let toolbarCollapsedTitleLeadingOffset: CGFloat = -11.5
    static let toolbarAddFolderWrapperWidth: CGFloat = 63
    static let toolbarSourceActionSymbolPointSize: CGFloat = 13
    static let toolbarNewNoteSymbolPointSize: CGFloat = 13
    static let toolbarCircularButtonSymbolPointSize: CGFloat = 12
    static let toolbarIconEnabledAlpha: CGFloat = 0.76
    static let toolbarIconDisabledAlpha: CGFloat = 0.42
    static let toolbarEditorToolIconDisabledAlpha: CGFloat = 1.0
    static let toolbarNoteListTitleWidth: CGFloat = 160
    static let toolbarNoteListTitleHeight: CGFloat = 46
    static let toolbarEditorToolsEnabledAlpha: CGFloat = 1.0
    static let toolbarEditorToolsDisabledAlpha: CGFloat = 0.42
    static let toolbarSymbolPointSize: CGFloat = 19
    static let sourceSymbolPointSize: CGFloat = 15
    static let windowScreenMargin: CGFloat = 72
    static let sourceRowHeight: CGFloat = 32
    static let sourceSectionHeaderHeight: CGFloat = 22
    static let sourceStatusRowHeight: CGFloat = 22
    static let sourceListTopInset: CGFloat = 12
    static let sourceListLeadingInset: CGFloat = 14
    static let sourceListBottomInset: CGFloat = 14
    static let sourceListTrailingInset: CGFloat = 6
    static let sourceSurfaceCornerRadius: CGFloat = 24
    static let sourceSurfaceDarkeningAlpha: CGFloat = 0.30
    static let sourceCollapseAnimationDuration: TimeInterval = 0.22
    static let sourceRowCornerRadius: CGFloat = 8
    static let sourceRowHighlightLeadingInset: CGFloat = 10
    static let sourceRowHighlightTrailingInset: CGFloat = 10
    static let sourceRowHighlightVerticalInset: CGFloat = 0
    static let sourceFolderIndentStep: CGFloat = 14
    static let sourceCellContentLeadingInset: CGFloat = 7.5
    static let sourceIconWidth: CGFloat = 22
    static let sourceIconHeight: CGFloat = 20
    static let sourceIconTitleSpacing: CGFloat = 3
    static let sourceGroupContentLeadingInset: CGFloat = 5
    static let sourceCountTrailingInset: CGFloat = 6
    static let sourceCountWidth: CGFloat = 32
    static let noteGroupRowHeight: CGFloat = 45
    static let noteRowHeight: CGFloat = 76
    static let sourceGroupFontSize: CGFloat = 12
    static let sourceButtonFontSize: CGFloat = 13.5
    static let sourceSelectedButtonFontWeight: NSFont.Weight = .regular
    static let sourceUnselectedButtonFontWeight: NSFont.Weight = .regular
    static let sourceButtonFontWeight: NSFont.Weight = sourceSelectedButtonFontWeight
    static let sourceCountFontSize: CGFloat = 13
    static let sourceSymbolWeight: NSFont.Weight = .medium
    static let noteGroupFontSize: CGFloat = 15
    static let noteGroupFontWeight: NSFont.Weight = .bold
    static let noteTitleFontSize: CGFloat = 14
    static let noteTitleFontWeight: NSFont.Weight = .bold
    static let noteSnippetFontSize: CGFloat = 12
    static let noteSnippetFontWeight: NSFont.Weight = .regular
    static let noteMetaFontSize: CGFloat = 11
    static let noteMetaFontWeight: NSFont.Weight = .medium
    static let galleryItemWidth: CGFloat = 154
    static let galleryItemHeight: CGFloat = 178
    static let galleryInteritemSpacing: CGFloat = 12
    static let galleryLineSpacing: CGFloat = 16
    static let galleryHorizontalInset: CGFloat = 18
    static let galleryVerticalInset: CGFloat = 14
    static let gallerySectionHeaderHeight: CGFloat = 32
    static let noteListHeaderTitleFontSize: CGFloat = 13
    static let noteListHeaderCountFontSize: CGFloat = 12
    static let noteListLeadingInset: CGFloat = 14
    static let noteListTrailingInset: CGFloat = 12
    static let noteListTopInset: CGFloat = 0
    static let noteListStackTopOffset: CGFloat = -1
    static let noteListBottomInset: CGFloat = 14
    static let editorTopInset: CGFloat = 6.25
    static let editorHorizontalInset: CGFloat = 23
    static let editorTextContainerHorizontalInset: CGFloat = 2
    static let editorBottomInset: CGFloat = 20
    static let editorDateRowHeight: CGFloat = 20
    static let editorDateToTitleSpacing: CGFloat = 10.75
    static let editorTitleToBodySpacing: CGFloat = 8
    static let editorStatusHorizontalOffset: CGFloat = -8.5
    static let editorStatusBottomGap: CGFloat = 6
    static let editorStatusFontSize: CGFloat = 13
    static let editorTitleFontSize: CGFloat = 24
    static let editorBodyFontSize: CGFloat = 15
    static let editorCodeFontSize: CGFloat = 14
    static let editorLineSpacing: CGFloat = 2.5
    static let editorParagraphSpacing: CGFloat = 6

    static func presentedWindowSize(in visibleFrame: NSRect) -> NSSize {
        let availableWidth = max(minimumWindowSize.width, visibleFrame.width - windowScreenMargin)
        let availableHeight = max(minimumWindowSize.height, visibleFrame.height - windowScreenMargin)
        return NSSize(
            width: min(presentedWindowSize.width, availableWidth),
            height: min(presentedWindowSize.height, availableHeight)
        )
    }

    static func presentedWindowSize(in visibleFrame: NSRect, usesCanonicalSize: Bool) -> NSSize {
        usesCanonicalSize ? presentedWindowSize : presentedWindowSize(in: visibleFrame)
    }

    static func clampedSourceColumnWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, sourceColumnMinimumWidth), sourceColumnMaximumWidth)
    }

    static func clampedNoteColumnWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, noteColumnMinimumWidth), noteColumnMaximumWidth)
    }

    static func migratedDefaultWindowFrame(_ frame: StoredWindowFrame?) -> StoredWindowFrame? {
        guard let frame else { return nil }
        let matchesPreviousDefault = previousDefaultWindowSizes.contains { size in
            abs(frame.width - size.width) < 0.5 && abs(frame.height - size.height) < 0.5
        }
        guard matchesPreviousDefault else { return frame }
        return StoredWindowFrame(
            x: frame.x + ((frame.width - presentedWindowSize.width) / 2),
            y: frame.y + ((frame.height - presentedWindowSize.height) / 2),
            width: presentedWindowSize.width,
            height: presentedWindowSize.height
        )
    }
}
