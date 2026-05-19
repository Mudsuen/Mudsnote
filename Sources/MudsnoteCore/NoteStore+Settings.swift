import Foundation

extension NoteStore {
    public var notesDirectory: URL {
        get {
            if let raw = defaults.string(forKey: NoteStoreDefaultsKey.notesDirectory), !raw.isEmpty {
                return URL(fileURLWithPath: raw, isDirectory: true)
            }
            return Self.defaultNotesDirectory(fileManager: fileManager)
        }
        set {
            defaults.set(newValue.path, forKey: NoteStoreDefaultsKey.notesDirectory)
        }
    }

    public var hotKeyString: String {
        get { defaults.string(forKey: NoteStoreDefaultsKey.hotKey) ?? "option+shift+n" }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.hotKey) }
    }

    public var floatingNoteHotKeyString: String {
        get { defaults.string(forKey: NoteStoreDefaultsKey.floatingHotKey) ?? "option+r" }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.floatingHotKey) }
    }

    public var saveShortcutString: String {
        get { defaults.string(forKey: NoteStoreDefaultsKey.saveShortcut) ?? "command+return" }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.saveShortcut) }
    }

    public var preferredDirectories: [URL] {
        deduplicatedDirectories([notesDirectory] + storedExtraDirectories())
    }

    public var panelOpacity: Double {
        get {
            let stored = defaults.object(forKey: NoteStoreDefaultsKey.panelOpacity) as? Double
            return min(max(stored ?? Self.defaultPanelOpacity, Self.minimumPanelOpacity), Self.maximumPanelOpacity)
        }
        set {
            defaults.set(min(max(newValue, Self.minimumPanelOpacity), Self.maximumPanelOpacity), forKey: NoteStoreDefaultsKey.panelOpacity)
        }
    }

    public var revealSavedNoteInFinder: Bool {
        get { defaults.object(forKey: NoteStoreDefaultsKey.revealSavedNoteInFinder) as? Bool ?? true }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.revealSavedNoteInFinder) }
    }

    public var floatingNoteStaysOnTop: Bool {
        get { defaults.object(forKey: NoteStoreDefaultsKey.floatingNoteStaysOnTop) as? Bool ?? true }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.floatingNoteStaysOnTop) }
    }

    public var spellCheckingEnabled: Bool {
        get { defaults.object(forKey: NoteStoreDefaultsKey.spellCheckingEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.spellCheckingEnabled) }
    }

    public var aiEnabled: Bool {
        get { defaults.object(forKey: NoteStoreDefaultsKey.aiEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.aiEnabled) }
    }

    public var aiOllamaBaseURLString: String {
        get { defaults.string(forKey: NoteStoreDefaultsKey.aiOllamaBaseURL) ?? "http://localhost:11434" }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.aiOllamaBaseURL) }
    }

    public var aiOllamaModel: String {
        get { defaults.string(forKey: NoteStoreDefaultsKey.aiOllamaModel) ?? "llama3.2" }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.aiOllamaModel) }
    }

    public var quickCaptureWindowFrame: StoredWindowFrame? {
        get {
            readStoredFrame(
                xKey: NoteStoreDefaultsKey.quickCaptureFrameX,
                yKey: NoteStoreDefaultsKey.quickCaptureFrameY,
                widthKey: NoteStoreDefaultsKey.quickCaptureFrameWidth,
                heightKey: NoteStoreDefaultsKey.quickCaptureFrameHeight
            )
        }
        set {
            writeStoredFrame(
                newValue,
                xKey: NoteStoreDefaultsKey.quickCaptureFrameX,
                yKey: NoteStoreDefaultsKey.quickCaptureFrameY,
                widthKey: NoteStoreDefaultsKey.quickCaptureFrameWidth,
                heightKey: NoteStoreDefaultsKey.quickCaptureFrameHeight
            )
        }
    }

    public var floatingNoteWindowFrame: StoredWindowFrame? {
        get {
            readStoredFrame(
                xKey: NoteStoreDefaultsKey.floatingFrameX,
                yKey: NoteStoreDefaultsKey.floatingFrameY,
                widthKey: NoteStoreDefaultsKey.floatingFrameWidth,
                heightKey: NoteStoreDefaultsKey.floatingFrameHeight
            )
        }
        set {
            writeStoredFrame(
                newValue,
                xKey: NoteStoreDefaultsKey.floatingFrameX,
                yKey: NoteStoreDefaultsKey.floatingFrameY,
                widthKey: NoteStoreDefaultsKey.floatingFrameWidth,
                heightKey: NoteStoreDefaultsKey.floatingFrameHeight
            )
        }
    }

    public var quickCaptureWindowOrigin: StoredWindowOrigin? {
        get {
            guard let frame = quickCaptureWindowFrame else { return nil }
            return StoredWindowOrigin(x: frame.x, y: frame.y)
        }
        set {
            guard let newValue else {
                quickCaptureWindowFrame = nil
                return
            }

            let current = quickCaptureWindowFrame
            quickCaptureWindowFrame = StoredWindowFrame(
                x: newValue.x,
                y: newValue.y,
                width: current?.width ?? 412,
                height: current?.height ?? 314
            )
        }
    }

    public func ensureNotesDirectory() throws {
        try fileManager.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
    }

    public func configurePreferredDirectories(_ directories: [URL], defaultDirectory: URL) {
        let normalizedDefault = defaultDirectory.standardizedFileURL
        notesDirectory = normalizedDefault

        let extras = deduplicatedDirectories(directories)
            .filter { $0.standardizedFileURL.path != normalizedDefault.path }
            .map(\.path)
        defaults.set(extras, forKey: NoteStoreDefaultsKey.extraDirectories)
    }

    public func addPreferredDirectory(_ directory: URL) {
        configurePreferredDirectories(preferredDirectories + [directory], defaultDirectory: notesDirectory)
    }

    func storedExtraDirectories() -> [URL] {
        ((defaults.array(forKey: NoteStoreDefaultsKey.extraDirectories) as? [String]) ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
    }

    private func readStoredFrame(xKey: String, yKey: String, widthKey: String, heightKey: String) -> StoredWindowFrame? {
        guard defaults.object(forKey: xKey) != nil,
              defaults.object(forKey: yKey) != nil,
              defaults.object(forKey: widthKey) != nil,
              defaults.object(forKey: heightKey) != nil else {
            return nil
        }

        return StoredWindowFrame(
            x: defaults.double(forKey: xKey),
            y: defaults.double(forKey: yKey),
            width: defaults.double(forKey: widthKey),
            height: defaults.double(forKey: heightKey)
        )
    }

    private func writeStoredFrame(_ frame: StoredWindowFrame?, xKey: String, yKey: String, widthKey: String, heightKey: String) {
        guard let frame else {
            defaults.removeObject(forKey: xKey)
            defaults.removeObject(forKey: yKey)
            defaults.removeObject(forKey: widthKey)
            defaults.removeObject(forKey: heightKey)
            return
        }

        defaults.set(frame.x, forKey: xKey)
        defaults.set(frame.y, forKey: yKey)
        defaults.set(frame.width, forKey: widthKey)
        defaults.set(frame.height, forKey: heightKey)
    }
}
