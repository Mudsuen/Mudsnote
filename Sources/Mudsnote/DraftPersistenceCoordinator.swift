import Foundation
import MudsnoteCore

enum DraftPersistenceAction: Sendable {
    case save(DraftSnapshot)
    case delete(String)
    case publish(DraftSnapshot, expectedContents: String)
}

final class DraftPersistenceCoordinator: @unchecked Sendable {
    typealias Completion = @MainActor @Sendable (Result<NoteUpdateResult?, Error>) -> Void
    typealias Save = @Sendable (DraftSnapshot) throws -> Void
    typealias Publish = @Sendable (DraftSnapshot, URL, String) throws -> NoteUpdateResult
    typealias Delete = @Sendable (String) -> Void

    private struct Request {
        let action: DraftPersistenceAction
        let completion: Completion
    }

    private let save: Save
    private let delete: Delete
    private let publish: Publish?
    // Accessed only by the serial persistence queue, including synchronous flushes.
    private var publishedNotes: [String: NoteUpdateResult] = [:]
    private let queue = DispatchQueue(
        label: "top.muds.mudsnote.draft-persistence",
        qos: .utility
    )
    private let lock = NSLock()
    private var pendingQueue: [Request] = []
    private var isWorkerScheduled = false

    init(
        save: @escaping Save,
        delete: @escaping Delete,
        publish: Publish? = nil
    ) {
        self.save = save
        self.delete = delete
        self.publish = publish
    }

    func enqueue(
        _ action: DraftPersistenceAction,
        completion: @escaping Completion
    ) {
        var supersededCompletions: [Completion] = []
        lock.lock()
        // Only coalesce back-to-back `.save` requests for the same draft ID so
        // `.delete` and `.publish` actions are never dropped or overwritten.
        if case .save(let incoming) = action,
           let last = pendingQueue.last,
           case .save(let existing) = last.action,
           existing.id == incoming.id {
            supersededCompletions.append(last.completion)
            pendingQueue[pendingQueue.count - 1] = Request(action: action, completion: completion)
        } else {
            pendingQueue.append(Request(action: action, completion: completion))
        }
        let shouldScheduleWorker = !isWorkerScheduled
        isWorkerScheduled = true
        lock.unlock()

        for superseded in supersededCompletions {
            Task { @MainActor in
                superseded(.success(nil))
            }
        }

        guard shouldScheduleWorker else { return }
        queue.async { [weak self] in
            self?.drainPendingRequests()
        }
    }

    @discardableResult
    func flush(_ action: DraftPersistenceAction) throws -> NoteUpdateResult? {
        lock.lock()
        let droppedRequests = pendingQueue
        pendingQueue.removeAll()
        lock.unlock()

        for request in droppedRequests {
            Task { @MainActor in
                request.completion(.success(nil))
            }
        }

        var result: Result<NoteUpdateResult?, Error> = .success(nil)
        queue.sync {
            result = Result {
                try perform(action)
            }
        }
        return try result.get()
    }

    func resetPublishedNotes() {
        queue.sync { publishedNotes.removeAll() }
    }

    func waitUntilIdle() {
        queue.sync {}
    }

    private func drainPendingRequests() {
        while true {
            lock.lock()
            guard !pendingQueue.isEmpty else {
                isWorkerScheduled = false
                lock.unlock()
                return
            }
            let request = pendingQueue.removeFirst()
            lock.unlock()

            let result = Result {
                try perform(request.action)
            }
            Task { @MainActor in
                request.completion(result)
            }
        }
    }

    private func perform(_ action: DraftPersistenceAction) throws -> NoteUpdateResult? {
        switch action {
        case .save(let snapshot):
            try save(snapshot)
        case .delete(let id):
            delete(id)
        case .publish(let snapshot, let expectedContents):
            // Keep a recoverable draft until the coordinated document write succeeds.
            try save(snapshot)
            guard let path = snapshot.sourcePath, let publish else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            let previous = publishedNotes[path]
            let result = try publish(snapshot, previous?.url ?? URL(fileURLWithPath: path),
                                     previous?.sourceContents ?? expectedContents)
            publishedNotes[path] = result
            publishedNotes[result.url.path] = result
            delete(snapshot.id)
            return result
        }
        return nil
    }
}
