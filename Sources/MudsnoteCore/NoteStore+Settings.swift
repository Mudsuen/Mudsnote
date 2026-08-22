import Foundation

extension NoteStore {
    public enum SearchDefaultScope: String, CaseIterable, Sendable {
        case allDirectories
        case defaultDirectory
    }

    public var notesDirectory: URL {
        get {
            if let raw = defaults.string(forKey: NoteStoreDefaultsKey.notesDirectory), !raw.isEmpty {
                return URL(fileURLWithPath: raw, isDirectory: true)
            }
            return Self.defaultNotesDirectory(fileManager: fileManager)
        }
        set {
            defaults.set(newValue.path, forKey: NoteStoreDefaultsKey.notesDirectory)
            migrateLegacyPinnedNotePathsIfPossible()
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

    public var themeColorIdentifier: String {
        get { defaults.string(forKey: NoteStoreDefaultsKey.themeColorIdentifier) ?? "ocean" }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.themeColorIdentifier) }
    }

    public var searchDefaultScope: SearchDefaultScope {
        get {
            guard let rawValue = defaults.string(forKey: NoteStoreDefaultsKey.searchDefaultScope) else {
                return .allDirectories
            }
            return SearchDefaultScope(rawValue: rawValue) ?? .allDirectories
        }
        set { defaults.set(newValue.rawValue, forKey: NoteStoreDefaultsKey.searchDefaultScope) }
    }

    public var includesArchivedNotesInSearchAndKnowledge: Bool {
        get {
            defaults.object(forKey: NoteStoreDefaultsKey.includesArchivedNotesInSearchAndKnowledge) as? Bool
                ?? false
        }
        set {
            defaults.set(newValue, forKey: NoteStoreDefaultsKey.includesArchivedNotesInSearchAndKnowledge)
        }
    }

    public var aiMemoryDailySyncEnabled: Bool {
        get { defaults.object(forKey: NoteStoreDefaultsKey.aiMemoryDailySyncEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.aiMemoryDailySyncEnabled) }
    }

    public var aiMemoryLastSyncDate: Date? {
        get { defaults.object(forKey: NoteStoreDefaultsKey.aiMemoryLastSyncDate) as? Date }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.aiMemoryLastSyncDate) }
    }

    public func isArchivedNote(at url: URL) -> Bool {
        let archiveNames = Set(["archive", "archives", "归档"])
        return url.standardizedFileURL.pathComponents.contains {
            archiveNames.contains($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }

    public var editorContextMenuItemIdentifiers: [String]? {
        get { defaults.array(forKey: NoteStoreDefaultsKey.editorContextMenuItems) as? [String] }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.editorContextMenuItems) }
    }

    public var selectionToolbarItemIdentifiers: [String]? {
        get { defaults.array(forKey: NoteStoreDefaultsKey.selectionToolbarItems) as? [String] }
        set { defaults.set(newValue, forKey: NoteStoreDefaultsKey.selectionToolbarItems) }
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

    public func libraryImageDisplayWidth(for fileURL: URL) -> Double? {
        let path = fileURL.standardizedFileURL.path
        guard let widths = defaults.dictionary(forKey: NoteStoreDefaultsKey.libraryImageDisplayWidths),
              let width = widths[path] as? NSNumber,
              width.doubleValue.isFinite,
              width.doubleValue > 0 else {
            return nil
        }
        return width.doubleValue
    }

    public func setLibraryImageDisplayWidth(_ width: Double?, for fileURL: URL) {
        let path = fileURL.standardizedFileURL.path
        var widths = defaults.dictionary(forKey: NoteStoreDefaultsKey.libraryImageDisplayWidths) ?? [:]
        if let width, width.isFinite, width > 0 {
            widths[path] = width
        } else {
            widths.removeValue(forKey: path)
        }
        defaults.set(widths, forKey: NoteStoreDefaultsKey.libraryImageDisplayWidths)
    }

    public var libraryCollapsedFolderPaths: Set<String> {
        get { storedStandardizedPathSet(forKey: NoteStoreDefaultsKey.libraryCollapsedFolderPaths) }
        set { storeStandardizedPathSet(newValue, forKey: NoteStoreDefaultsKey.libraryCollapsedFolderPaths) }
    }

    public var libraryExpandedFolderPaths: Set<String> {
        get { storedStandardizedPathSet(forKey: NoteStoreDefaultsKey.libraryExpandedFolderPaths) }
        set { storeStandardizedPathSet(newValue, forKey: NoteStoreDefaultsKey.libraryExpandedFolderPaths) }
    }

    public var libraryFolderOrderPaths: [String] {
        get {
            var seen = Set<String>()
            return (defaults.stringArray(forKey: NoteStoreDefaultsKey.libraryFolderOrderPaths) ?? []).compactMap {
                let path = URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path
                return seen.insert(path).inserted ? path : nil
            }
        }
        set {
            var seen = Set<String>()
            let paths = newValue.compactMap {
                let path = URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path
                return seen.insert(path).inserted ? path : nil
            }
            defaults.set(paths, forKey: NoteStoreDefaultsKey.libraryFolderOrderPaths)
        }
    }

    public func libraryFolderIconName(for directory: URL) -> String? {
        let path = directory.standardizedFileURL.path
        guard let iconName = libraryFolderIconNames[path]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !iconName.isEmpty else {
            return nil
        }
        return iconName
    }

    public func setLibraryFolderIconName(_ iconName: String?, for directory: URL) {
        let path = directory.standardizedFileURL.path
        var iconNames = libraryFolderIconNames
        if let iconName = iconName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !iconName.isEmpty {
            iconNames[path] = iconName
        } else {
            iconNames.removeValue(forKey: path)
        }
        defaults.set(iconNames, forKey: NoteStoreDefaultsKey.libraryFolderIconNames)
    }

    public func replaceLibraryFolderOrderPathPrefix(_ oldDirectory: URL, with newDirectory: URL) {
        let oldPath = oldDirectory.standardizedFileURL.path
        let newPath = newDirectory.standardizedFileURL.path
        libraryFolderOrderPaths = libraryFolderOrderPaths.map { path in
            guard path == oldPath || path.hasPrefix(oldPath + "/") else { return path }
            return newPath + String(path.dropFirst(oldPath.count))
        }
    }

    func replaceLibraryFolderIconPathPrefix(_ oldDirectory: URL, with newDirectory: URL) {
        let oldPath = oldDirectory.standardizedFileURL.path
        let newPath = newDirectory.standardizedFileURL.path
        var remapped: [String: String] = [:]
        for (path, iconName) in libraryFolderIconNames {
            if path == oldPath || path.hasPrefix(oldPath + "/") {
                remapped[newPath + String(path.dropFirst(oldPath.count))] = iconName
            } else {
                remapped[path] = iconName
            }
        }
        defaults.set(remapped, forKey: NoteStoreDefaultsKey.libraryFolderIconNames)
    }

    func removeLibraryFolderIconNames(in directory: URL) {
        let directoryPath = directory.standardizedFileURL.path
        let remaining = libraryFolderIconNames.filter { path, _ in
            path != directoryPath && !path.hasPrefix(directoryPath + "/")
        }
        defaults.set(remaining, forKey: NoteStoreDefaultsKey.libraryFolderIconNames)
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
        migrateLegacyPinnedNotePathsIfPossible()
        let localPaths = defaults.stringArray(
            forKey: NoteStoreDefaultsKey.libraryPinnedNotePaths
        ) ?? []
        var paths = Set(localPaths.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        })
        for root in preferredDirectories {
            for relativePath in loadSharedPinnedNotePaths(in: root) {
                paths.insert(
                    root.appendingPathComponent(relativePath)
                        .standardizedFileURL
                        .path
                )
            }
        }
        return paths.sorted()
    }

    public func isLibraryNotePinned(at url: URL) -> Bool {
        libraryPinnedNotePaths.contains(url.standardizedFileURL.path)
    }

    public func setLibraryNotePinned(_ isPinned: Bool, at url: URL) {
        let standardizedURL = url.standardizedFileURL
        let path = standardizedURL.path
        if let root = owningPreferredDirectory(for: standardizedURL),
           let relativePath = relativeNotePath(for: standardizedURL, in: root) {
            do {
                var paths = loadSharedPinnedNotePaths(in: root)
                if isPinned {
                    paths.insert(relativePath)
                } else {
                    paths.remove(relativePath)
                }
                try saveSharedPinnedNotePaths(paths, in: root)
                removeLocalPinnedNotePath(path)
                return
            } catch {
                // Preserve the existing local behavior if the shared library is
                // temporarily unavailable.
            }
        }
        var localPaths = localPinnedNotePaths()
        if isPinned {
            localPaths.insert(path)
        } else {
            localPaths.remove(path)
        }
        defaults.set(localPaths.sorted(), forKey: NoteStoreDefaultsKey.libraryPinnedNotePaths)
    }

    func replaceLibraryPinnedNotePath(_ oldURL: URL, with newURL: URL) {
        guard isLibraryNotePinned(at: oldURL) else { return }
        setLibraryNotePinned(false, at: oldURL)
        setLibraryNotePinned(true, at: newURL)
    }

    func replaceLibraryPinnedNotePathPrefix(_ oldDirectory: URL, with newDirectory: URL) {
        let oldPath = oldDirectory.standardizedFileURL.path
        let newPath = newDirectory.standardizedFileURL.path
        let affectedPaths = libraryPinnedNotePaths.filter {
            $0.hasPrefix(oldPath + "/")
        }
        for path in affectedPaths {
            setLibraryNotePinned(false, at: URL(fileURLWithPath: path))
            setLibraryNotePinned(
                true,
                at: URL(
                    fileURLWithPath: newPath + String(path.dropFirst(oldPath.count))
                )
            )
        }
    }

    public func removeLibraryPinnedNotePaths(in directory: URL) {
        let directoryPath = directory.standardizedFileURL.path
        let affectedPaths = libraryPinnedNotePaths.filter {
            $0 == directoryPath || $0.hasPrefix(directoryPath + "/")
        }
        for path in affectedPaths {
            setLibraryNotePinned(false, at: URL(fileURLWithPath: path))
        }
    }

    private func localPinnedNotePaths() -> Set<String> {
        Set(
            (defaults.stringArray(forKey: NoteStoreDefaultsKey.libraryPinnedNotePaths) ?? [])
                .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        )
    }

    private func removeLocalPinnedNotePath(_ path: String) {
        var paths = localPinnedNotePaths()
        guard paths.remove(path) != nil else { return }
        defaults.set(paths.sorted(), forKey: NoteStoreDefaultsKey.libraryPinnedNotePaths)
    }

    private func owningPreferredDirectory(for url: URL) -> URL? {
        let path = url.standardizedFileURL.path
        return preferredDirectories
            .filter {
                let rootPath = $0.standardizedFileURL.path
                return path.hasPrefix(rootPath + "/")
            }
            .max {
                $0.standardizedFileURL.path.count
                    < $1.standardizedFileURL.path.count
            }
    }

    private func relativeNotePath(for url: URL, in root: URL) -> String? {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return nil }
        let relativePath = String(path.dropFirst(rootPath.count + 1))
        guard relativePath.hasSuffix(".md"),
              !relativePath.hasPrefix("Attachments/"),
              !relativePath.hasPrefix(".mudsnote/") else { return nil }
        return relativePath
    }

    private func loadSharedPinnedNotePaths(in root: URL) -> Set<String> {
        let url = root.appendingPathComponent(".mudsnote/pins.json")
        guard fileManager.fileExists(atPath: url.path),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 1_048_576,
              let data = try? Data(contentsOf: url),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(paths.filter {
            $0.hasSuffix(".md")
                && !$0.hasPrefix("Attachments/")
                && !$0.hasPrefix(".mudsnote/")
        })
    }

    private func saveSharedPinnedNotePaths(_ paths: Set<String>, in root: URL) throws {
        let directory = root.appendingPathComponent(".mudsnote", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(paths.sorted()).write(
            to: directory.appendingPathComponent("pins.json"),
            options: .atomic
        )
    }

    private func migrateLegacyPinnedNotePathsIfPossible() {
        let legacyPaths = localPinnedNotePaths()
        guard !legacyPaths.isEmpty else { return }
        var remaining = legacyPaths
        for path in legacyPaths {
            let url = URL(fileURLWithPath: path)
            guard let root = owningPreferredDirectory(for: url),
                  let relativePath = relativeNotePath(for: url, in: root),
                  fileManager.fileExists(atPath: root.path) else { continue }
            do {
                var paths = loadSharedPinnedNotePaths(in: root)
                paths.insert(relativePath)
                try saveSharedPinnedNotePaths(paths, in: root)
                remaining.remove(path)
            } catch {
                continue
            }
        }
        defaults.set(remaining.sorted(), forKey: NoteStoreDefaultsKey.libraryPinnedNotePaths)
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
        migrateLegacyPinnedNotePathsIfPossible()
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
        replaceLibraryFolderIconPathPrefix(oldDirectory, with: normalizedNew)
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

    private var libraryFolderIconNames: [String: String] {
        (defaults.dictionary(forKey: NoteStoreDefaultsKey.libraryFolderIconNames) ?? [:]).reduce(into: [:]) {
            result, entry in
            guard let iconName = entry.value as? String else { return }
            let path = URL(fileURLWithPath: entry.key, isDirectory: true).standardizedFileURL.path
            result[path] = iconName
        }
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
