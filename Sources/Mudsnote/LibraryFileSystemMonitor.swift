import CoreServices
import Foundation

struct LibraryFileSystemChange: Hashable, Sendable {
    private static let supportedNoteFileExtensions = Set(["md", "markdown", "txt"])
    private static let imageFileExtensions = Set([
        "apng", "avif", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff", "webp"
    ])
    private static let unconditionalFullRescanFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagUserDropped
            | kFSEventStreamEventFlagKernelDropped
            | kFSEventStreamEventFlagEventIdsWrapped
    )
    private static let fullRescanFlags = FSEventStreamEventFlags(
        unconditionalFullRescanFlags
            | FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
    )

    let path: String
    let flags: FSEventStreamEventFlags

    var isMarkdownFile: Bool {
        Self.supportedNoteFileExtensions.contains(
            URL(fileURLWithPath: path).pathExtension.lowercased()
        )
    }

    var requiresFullRescan: Bool {
        flags & Self.fullRescanFlags != 0
    }

    var isImageFile: Bool {
        Self.imageFileExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    var requiresUnconditionalFullRescan: Bool {
        flags & Self.unconditionalFullRescanFlags != 0
    }

    var changesDirectoryStructure: Bool {
        if requiresFullRescan {
            return true
        }
        let isDirectory = flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0
        let structuralFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemCreated
                | kFSEventStreamEventFlagItemRemoved
                | kFSEventStreamEventFlagItemRenamed
        )
        return isDirectory && flags & structuralFlags != 0
    }

    var requiresLibraryRefresh: Bool {
        isMarkdownFile || isImageFile || changesDirectoryStructure
    }
}

final class LibraryFileSystemMonitor: @unchecked Sendable {
    typealias ChangeHandler = @Sendable (Set<LibraryFileSystemChange>) -> Void

    private let roots: [String]
    private let rootPathMappings: [(physical: String, logical: String)]
    private let latency: CFTimeInterval
    private let debounceInterval: DispatchTimeInterval
    private let handler: ChangeHandler
    private let queue = DispatchQueue(label: "local.codex.mudsnote.library-file-events", qos: .utility)
    private let streamLock = NSLock()
    private var stream: FSEventStreamRef?
    private var pendingChanges: [String: LibraryFileSystemChange] = [:]
    private var deliveryWorkItem: DispatchWorkItem?

    init(
        roots: [URL],
        latency: CFTimeInterval = 0.18,
        debounceInterval: DispatchTimeInterval = .milliseconds(140),
        handler: @escaping ChangeHandler
    ) {
        var seenPaths = Set<String>()
        let rootPaths = roots.compactMap { root -> String? in
            let path = root.standardizedFileURL.path
            guard seenPaths.insert(path).inserted else { return nil }
            return path
        }
        self.roots = rootPaths
        self.rootPathMappings = rootPaths.map { path in
            // Foundation can collapse /private/tmp back to /tmp; FSEvents uses
            // the actual filesystem spelling returned by realpath.
            guard let resolved = realpath(path, nil) else { return (physical: path, logical: path) }
            defer { free(resolved) }
            return (physical: String(cString: resolved), logical: path)
        }.sorted { $0.physical.count > $1.physical.count }
        self.latency = latency
        self.debounceInterval = debounceInterval
        self.handler = handler
    }

    deinit {
        stop()
    }

    @discardableResult
    func start() -> Bool {
        streamLock.lock()
        defer { streamLock.unlock() }
        guard stream == nil, !roots.isEmpty else { return stream != nil }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagNoDefer
        )
        guard let createdStream = FSEventStreamCreate(
            nil,
            Self.eventCallback,
            &context,
            roots as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            return false
        }

        FSEventStreamSetDispatchQueue(createdStream, queue)
        guard FSEventStreamStart(createdStream) else {
            FSEventStreamInvalidate(createdStream)
            FSEventStreamRelease(createdStream)
            return false
        }
        stream = createdStream
        return true
    }

    func stop() {
        streamLock.lock()
        let activeStream = stream
        stream = nil
        streamLock.unlock()

        if let activeStream {
            FSEventStreamStop(activeStream)
            FSEventStreamInvalidate(activeStream)
            FSEventStreamRelease(activeStream)
        }

        queue.async { [weak self] in
            self?.deliveryWorkItem?.cancel()
            self?.deliveryWorkItem = nil
            self?.pendingChanges.removeAll()
        }
    }

    private static let eventCallback: FSEventStreamCallback = {
        _, clientInfo, eventCount, eventPaths, eventFlags, _ in
        guard let clientInfo else { return }
        let monitor = Unmanaged<LibraryFileSystemMonitor>
            .fromOpaque(clientInfo)
            .takeUnretainedValue()
        let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
        guard !paths.isEmpty else { return }

        let changes = (0..<min(eventCount, paths.count)).compactMap { index -> LibraryFileSystemChange? in
            let change = LibraryFileSystemChange(path: monitor.libraryPath(for: paths[index]), flags: eventFlags[index])
            return change.requiresLibraryRefresh ? change : nil
        }
        monitor.enqueue(changes)
    }

    // FSEvents reports physical paths, while note and preview caches use the
    // user's registered root. Keep that spelling even after a file is removed.
    func libraryPath(for eventPath: String) -> String {
        for mapping in rootPathMappings {
            if eventPath == mapping.physical { return mapping.logical }
            if eventPath.hasPrefix(mapping.physical + "/") {
                return mapping.logical + eventPath.dropFirst(mapping.physical.count)
            }
        }
        return eventPath
    }

    private func enqueue(_ changes: [LibraryFileSystemChange]) {
        guard !changes.isEmpty else { return }
        for change in changes {
            if let existing = pendingChanges[change.path] {
                pendingChanges[change.path] = LibraryFileSystemChange(
                    path: change.path,
                    flags: existing.flags | change.flags
                )
            } else {
                pendingChanges[change.path] = change
            }
        }

        deliveryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let changes = Set(self.pendingChanges.values)
            self.pendingChanges.removeAll()
            self.deliveryWorkItem = nil
            guard !changes.isEmpty else { return }
            self.handler(changes)
        }
        deliveryWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}
