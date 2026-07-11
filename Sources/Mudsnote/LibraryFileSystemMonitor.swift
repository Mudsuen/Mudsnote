import CoreServices
import Foundation

struct LibraryFileSystemChange: Hashable, Sendable {
    let path: String
    let flags: FSEventStreamEventFlags

    var isMarkdownFile: Bool {
        URL(fileURLWithPath: path).pathExtension.localizedCaseInsensitiveCompare("md") == .orderedSame
    }

    var changesDirectoryStructure: Bool {
        let isDirectory = flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0
        let structuralFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemCreated
                | kFSEventStreamEventFlagItemRemoved
                | kFSEventStreamEventFlagItemRenamed
                | kFSEventStreamEventFlagRootChanged
                | kFSEventStreamEventFlagMustScanSubDirs
        )
        return isDirectory && flags & structuralFlags != 0
    }

    var requiresLibraryRefresh: Bool {
        isMarkdownFile || changesDirectoryStructure
    }
}

final class LibraryFileSystemMonitor: @unchecked Sendable {
    typealias ChangeHandler = @Sendable (Set<LibraryFileSystemChange>) -> Void

    private let roots: [String]
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
        self.roots = roots.compactMap { root in
            let path = root.standardizedFileURL.path
            guard seenPaths.insert(path).inserted else { return nil }
            return path
        }
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
            let change = LibraryFileSystemChange(path: paths[index], flags: eventFlags[index])
            return change.requiresLibraryRefresh ? change : nil
        }
        monitor.enqueue(changes)
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
