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
        get { defaults.object(forKey: NoteStoreDefaultsKey.revealSavedNoteInFinder) as? Bool ?? false }
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

    public var libraryNoteSortOrderRawValue: Int {
        get { defaults.object(forKey: NoteStoreDefaultsKey.libraryNoteSortOrder) as? Int ?? 0 }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.libraryNoteSortOrder) }
    }

    public var libraryGroupsNotesByDate: Bool {
        get { defaults.object(forKey: NoteStoreDefaultsKey.libraryGroupsNotesByDate) as? Bool ?? true }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.libraryGroupsNotesByDate) }
    }

    public var libraryNoteViewModeRawValue: Int {
        get { defaults.object(forKey: NoteStoreDefaultsKey.libraryNoteViewMode) as? Int ?? 0 }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.libraryNoteViewMode) }
    }

    public var libraryIncludesSubfolderNotes: Bool {
        get { defaults.object(forKey: NoteStoreDefaultsKey.libraryIncludesSubfolderNotes) as? Bool ?? true }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.libraryIncludesSubfolderNotes) }
    }

    public var libraryCollapsedFolderPaths: Set<String> {
        get { storedStandardizedPathSet(forKey: NoteStoreDefaultsKey.libraryCollapsedFolderPaths) }
        set { storeStandardizedPathSet(newValue, forKey: NoteStoreDefaultsKey.libraryCollapsedFolderPaths) }
    }

    public var libraryExpandedFolderPaths: Set<String> {
        get { storedStandardizedPathSet(forKey: NoteStoreDefaultsKey.libraryExpandedFolderPaths) }
        set { storeStandardizedPathSet(newValue, forKey: NoteStoreDefaultsKey.libraryExpandedFolderPaths) }
    }

    public var libraryFoldersSectionCollapsed: Bool {
        get { defaults.object(forKey: NoteStoreDefaultsKey.libraryFoldersSectionCollapsed) as? Bool ?? false }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.libraryFoldersSectionCollapsed) }
    }

    public var libraryTagsSectionCollapsed: Bool {
        get { defaults.object(forKey: NoteStoreDefaultsKey.libraryTagsSectionCollapsed) as? Bool ?? false }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.libraryTagsSectionCollapsed) }
    }

    public var librarySourceColumnWidth: Double? {
        get { storedPositiveFiniteDouble(forKey: NoteStoreDefaultsKey.librarySourceColumnWidth) }
        set { storeOptionalFiniteDouble(newValue, forKey: NoteStoreDefaultsKey.librarySourceColumnWidth) }
    }

    public var libraryNoteColumnWidth: Double? {
        get { storedPositiveFiniteDouble(forKey: NoteStoreDefaultsKey.libraryNoteColumnWidth) }
        set { storeOptionalFiniteDouble(newValue, forKey: NoteStoreDefaultsKey.libraryNoteColumnWidth) }
    }

    public var librarySourceListVisible: Bool {
        get { defaults.object(forKey: NoteStoreDefaultsKey.librarySourceListVisible) as? Bool ?? true }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.librarySourceListVisible) }
    }

    @discardableResult
    public func migrateLibraryLayoutScaleIfNeeded(
        to version: Int,
        replacingDefaultPaneWidths previousDefaults: (source: Double, note: Double)? = nil
    ) -> Bool {
        let currentVersion = defaults.integer(forKey: NoteStoreDefaultsKey.libraryLayoutScaleVersion)
        guard currentVersion < version else {
            return false
        }

        if currentVersion + 1 == version, let previousDefaults {
            if librarySourceColumnWidth.map({ abs($0 - previousDefaults.source) < 0.5 }) ?? false {
                defaults.removeObject(forKey: NoteStoreDefaultsKey.librarySourceColumnWidth)
            }
            if libraryNoteColumnWidth.map({ abs($0 - previousDefaults.note) < 0.5 }) ?? false {
                defaults.removeObject(forKey: NoteStoreDefaultsKey.libraryNoteColumnWidth)
            }
        } else {
            defaults.removeObject(forKey: NoteStoreDefaultsKey.librarySourceColumnWidth)
            defaults.removeObject(forKey: NoteStoreDefaultsKey.libraryNoteColumnWidth)
        }
        defaults.set(version, forKey: NoteStoreDefaultsKey.libraryLayoutScaleVersion)
        return true
    }

    public var libraryPinnedNotePaths: [String] {
        let storedPaths = defaults.stringArray(forKey: NoteStoreDefaultsKey.libraryPinnedNotePaths) ?? []
        return Array(Set(storedPaths.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        })).sorted()
    }

    public func isLibraryNotePinned(at url: URL) -> Bool {
        libraryPinnedNotePaths.contains(url.standardizedFileURL.path)
    }

    public func setLibraryNotePinned(_ isPinned: Bool, at url: URL) {
        var paths = Set(libraryPinnedNotePaths)
        let path = url.standardizedFileURL.path
        if isPinned {
            paths.insert(path)
        } else {
            paths.remove(path)
        }
        defaults.set(paths.sorted(), forKey: NoteStoreDefaultsKey.libraryPinnedNotePaths)
    }

    func replaceLibraryPinnedNotePath(_ oldURL: URL, with newURL: URL) {
        let oldPath = oldURL.standardizedFileURL.path
        guard libraryPinnedNotePaths.contains(oldPath) else { return }
        var paths = Set(libraryPinnedNotePaths)
        paths.remove(oldPath)
        paths.insert(newURL.standardizedFileURL.path)
        defaults.set(paths.sorted(), forKey: NoteStoreDefaultsKey.libraryPinnedNotePaths)
    }

    func replaceLibraryPinnedNotePathPrefix(_ oldDirectory: URL, with newDirectory: URL) {
        let oldPath = oldDirectory.standardizedFileURL.path
        let newPath = newDirectory.standardizedFileURL.path
        let updatedPaths = libraryPinnedNotePaths.map { path in
            guard path.hasPrefix(oldPath + "/") else { return path }
            return newPath + String(path.dropFirst(oldPath.count))
        }
        defaults.set(Array(Set(updatedPaths)).sorted(), forKey: NoteStoreDefaultsKey.libraryPinnedNotePaths)
    }

    public func removeLibraryPinnedNotePaths(in directory: URL) {
        let directoryPath = directory.standardizedFileURL.path
        let remainingPaths = libraryPinnedNotePaths.filter {
            $0 != directoryPath && !$0.hasPrefix(directoryPath + "/")
        }
        defaults.set(remainingPaths, forKey: NoteStoreDefaultsKey.libraryPinnedNotePaths)
    }

    func replaceLibraryFolderDisclosurePathPrefix(_ oldDirectory: URL, with newDirectory: URL) {
        let oldPath = oldDirectory.standardizedFileURL.path
        let newPath = newDirectory.standardizedFileURL.path
        libraryCollapsedFolderPaths = replacingPathPrefix(
            oldPath,
            with: newPath,
            in: libraryCollapsedFolderPaths
        )
        libraryExpandedFolderPaths = replacingPathPrefix(
            oldPath,
            with: newPath,
            in: libraryExpandedFolderPaths
        )
    }

    public func removeLibraryFolderDisclosurePaths(in directory: URL) {
        let directoryPath = directory.standardizedFileURL.path
        libraryCollapsedFolderPaths = libraryCollapsedFolderPaths.filter {
            $0 != directoryPath && !$0.hasPrefix(directoryPath + "/")
        }
        libraryExpandedFolderPaths = libraryExpandedFolderPaths.filter {
            $0 != directoryPath && !$0.hasPrefix(directoryPath + "/")
        }
    }

    public var aiEnabled: Bool {
        get { defaults.object(forKey: NoteStoreDefaultsKey.aiEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.aiEnabled) }
    }

    public var aiCodexExecutablePath: String {
        get { defaults.string(forKey: NoteStoreDefaultsKey.aiCodexExecutablePath) ?? "" }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.aiCodexExecutablePath) }
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

    public var libraryWindowFrame: StoredWindowFrame? {
        get {
            readStoredFrame(
                xKey: NoteStoreDefaultsKey.libraryFrameX,
                yKey: NoteStoreDefaultsKey.libraryFrameY,
                widthKey: NoteStoreDefaultsKey.libraryFrameWidth,
                heightKey: NoteStoreDefaultsKey.libraryFrameHeight
            )
        }
        set {
            writeStoredFrame(
                newValue,
                xKey: NoteStoreDefaultsKey.libraryFrameX,
                yKey: NoteStoreDefaultsKey.libraryFrameY,
                widthKey: NoteStoreDefaultsKey.libraryFrameWidth,
                heightKey: NoteStoreDefaultsKey.libraryFrameHeight
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

    public func replacePreferredDirectory(_ oldDirectory: URL, with newDirectory: URL) {
        let oldPath = oldDirectory.standardizedFileURL.path
        let normalizedNew = newDirectory.standardizedFileURL
        let defaultDirectory = notesDirectory.standardizedFileURL.path == oldPath ? normalizedNew : notesDirectory
        let updatedDirectories = preferredDirectories.map { directory in
            let path = directory.standardizedFileURL.path
            if path == oldPath {
                return normalizedNew
            }
            if path.hasPrefix(oldPath + "/") {
                return URL(fileURLWithPath: normalizedNew.path + String(path.dropFirst(oldPath.count)), isDirectory: true)
                    .standardizedFileURL
            }
            return directory
        }
        configurePreferredDirectories(updatedDirectories, defaultDirectory: defaultDirectory)
    }

    public func removePreferredDirectory(_ directory: URL) {
        let directoryPath = directory.standardizedFileURL.path
        guard notesDirectory.standardizedFileURL.path != directoryPath else { return }
        let updatedDirectories = preferredDirectories.filter {
            let path = $0.standardizedFileURL.path
            return path != directoryPath && !path.hasPrefix(directoryPath + "/")
        }
        configurePreferredDirectories(updatedDirectories, defaultDirectory: notesDirectory)
    }

    func storedExtraDirectories() -> [URL] {
        ((defaults.array(forKey: NoteStoreDefaultsKey.extraDirectories) as? [String]) ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
    }

    private func storedStandardizedPathSet(forKey key: String) -> Set<String> {
        Set((defaults.stringArray(forKey: key) ?? []).map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path
        })
    }

    private func storeStandardizedPathSet(_ paths: Set<String>, forKey key: String) {
        let standardized = Set(paths.map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path
        })
        defaults.set(standardized.sorted(), forKey: key)
    }

    private func replacingPathPrefix(_ oldPath: String, with newPath: String, in paths: Set<String>) -> Set<String> {
        Set(paths.map { path in
            guard path == oldPath || path.hasPrefix(oldPath + "/") else { return path }
            return newPath + String(path.dropFirst(oldPath.count))
        })
    }

    private func storedPositiveFiniteDouble(forKey key: String) -> Double? {
        guard let value = defaults.object(forKey: key) as? Double,
              value.isFinite,
              value > 0 else {
            return nil
        }
        return value
    }

    private func storeOptionalFiniteDouble(_ value: Double?, forKey key: String) {
        guard let value, value.isFinite, value > 0 else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(value, forKey: key)
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
