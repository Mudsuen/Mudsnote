import AppKit
import MudsnoteCore

struct LibraryGallerySection {
    let title: String?
    var notes: [NoteSearchResult]
}

enum LibraryGalleryProjection {
    static func sections(from rows: [LibraryNoteListRow]) -> [LibraryGallerySection] {
        var sections: [LibraryGallerySection] = []
        var pendingTitle: String?
        var pendingNotes: [NoteSearchResult] = []

        func appendPendingSection() {
            guard !pendingNotes.isEmpty else { return }
            sections.append(LibraryGallerySection(title: pendingTitle, notes: pendingNotes))
            pendingNotes.removeAll(keepingCapacity: true)
        }

        for row in rows {
            switch row {
            case .group(let title):
                appendPendingSection()
                pendingTitle = title
            case .note(let note):
                pendingNotes.append(note)
            }
        }
        appendPendingSection()
        return sections
    }
}

@MainActor
final class LibraryGalleryCollectionView: NSCollectionView {
    var onKeyCommand: ((LibraryNoteKeyCommand) -> Bool)?
    var onContextMenu: ((IndexPath) -> NSMenu?)?

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else {
            super.keyDown(with: event)
            return
        }

        let command: LibraryNoteKeyCommand?
        switch event.keyCode {
        case 36, 76:
            command = .open
        case 51, 117:
            command = .delete
        default:
            command = nil
        }
        if let command, onKeyCommand?(command) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        guard let indexPath = indexPathForItem(at: location) else {
            return super.menu(for: event)
        }
        if !selectionIndexPaths.contains(indexPath) {
            selectionIndexPaths = [indexPath]
        }
        return onContextMenu?(indexPath) ?? super.menu(for: event)
    }
}

@MainActor
final class LibraryGalleryItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("LibraryGalleryItem")

    let previewSurface = NSView()
    let previewImageView = NSImageView()
    let previewTextLabel = NSTextField(wrappingLabelWithString: "")
    let titleLabel = NSTextField(labelWithString: "")
    let dateLabel = NSTextField(labelWithString: "")
    let folderImageView = NSImageView()
    let metadataLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.cornerRadius = 6

        previewSurface.wantsLayer = true
        previewSurface.layer?.backgroundColor = NSColor(calibratedWhite: 0.92, alpha: 1).cgColor
        previewSurface.layer?.cornerRadius = 6
        previewSurface.layer?.masksToBounds = true
        previewSurface.layer?.borderWidth = 1
        previewSurface.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.wantsLayer = true
        previewImageView.layer?.cornerRadius = 5
        previewImageView.layer?.masksToBounds = true

        previewTextLabel.font = .systemFont(ofSize: 12, weight: .regular)
        previewTextLabel.textColor = NSColor(calibratedWhite: 0.16, alpha: 1)
        previewTextLabel.maximumNumberOfLines = 7
        previewTextLabel.lineBreakMode = .byTruncatingTail

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = panelPrimaryTextColor()
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        dateLabel.font = .systemFont(ofSize: 11, weight: .regular)
        dateLabel.textColor = panelSecondaryTextColor()
        dateLabel.maximumNumberOfLines = 1
        dateLabel.lineBreakMode = .byTruncatingTail

        folderImageView.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "文件夹")
        folderImageView.contentTintColor = panelTertiaryTextColor()
        folderImageView.imageScaling = .scaleProportionallyDown

        metadataLabel.font = .systemFont(ofSize: 10, weight: .medium)
        metadataLabel.textColor = panelTertiaryTextColor()
        metadataLabel.maximumNumberOfLines = 1
        metadataLabel.lineBreakMode = .byTruncatingMiddle

        previewSurface.addSubview(previewImageView)
        previewSurface.addSubview(previewTextLabel)
        let metadataRow = NSStackView(views: [folderImageView, metadataLabel])
        metadataRow.orientation = .horizontal
        metadataRow.alignment = .centerY
        metadataRow.spacing = 4
        let textStack = NSStackView(views: [titleLabel, dateLabel, metadataRow])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        let stack = NSStackView(views: [previewSurface, textStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        root.addSubview(stack)

        for view in [previewImageView, previewTextLabel, stack] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        metadataRow.translatesAutoresizingMaskIntoConstraints = false
        textStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),
            previewSurface.widthAnchor.constraint(equalTo: stack.widthAnchor),
            textStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            previewSurface.heightAnchor.constraint(equalTo: previewSurface.widthAnchor, multiplier: 0.72),
            previewImageView.leadingAnchor.constraint(equalTo: previewSurface.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: previewSurface.trailingAnchor),
            previewImageView.topAnchor.constraint(equalTo: previewSurface.topAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: previewSurface.bottomAnchor),
            previewTextLabel.leadingAnchor.constraint(equalTo: previewSurface.leadingAnchor, constant: 10),
            previewTextLabel.trailingAnchor.constraint(equalTo: previewSurface.trailingAnchor, constant: -10),
            previewTextLabel.topAnchor.constraint(equalTo: previewSurface.topAnchor, constant: 9),
            previewTextLabel.bottomAnchor.constraint(lessThanOrEqualTo: previewSurface.bottomAnchor, constant: -9),
            titleLabel.widthAnchor.constraint(equalTo: textStack.widthAnchor),
            dateLabel.widthAnchor.constraint(equalTo: textStack.widthAnchor),
            metadataRow.widthAnchor.constraint(equalTo: textStack.widthAnchor),
            folderImageView.widthAnchor.constraint(equalToConstant: 11),
            folderImageView.heightAnchor.constraint(equalToConstant: 11)
        ])

        view = root
        updateSelectionAppearance()
    }

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    func configure(
        title: String,
        preview: String,
        date: String,
        metadata: String,
        thumbnail: NSImage?
    ) {
        titleLabel.stringValue = title
        previewTextLabel.stringValue = preview
        dateLabel.stringValue = date
        metadataLabel.stringValue = metadata
        previewImageView.image = thumbnail
        previewImageView.isHidden = thumbnail == nil
        previewTextLabel.isHidden = thumbnail != nil
        view.setAccessibilityLabel("\(title), \(date), \(metadata)")
    }

    private func updateSelectionAppearance() {
        guard isViewLoaded else { return }
        previewSurface.layer?.borderWidth = isSelected ? 2 : 1
        previewSurface.layer?.borderColor = isSelected
            ? panelAccentColor().cgColor
            : NSColor.white.withAlphaComponent(0.12).cgColor
    }
}

@MainActor
final class LibraryGallerySectionHeaderView: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("LibraryGallerySectionHeader")
    let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = panelPrimaryTextColor()
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: LibraryNotesLayout.galleryHorizontalInset
            ),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
