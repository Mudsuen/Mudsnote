import Foundation
import MudsnoteCore

enum DraftPersistenceAction: Sendable {
    case save(DraftSnapshot)
    case delete(String)
}

final class DraftPersistenceCoordinator: @unchecked Sendable {
    typealias Completion = @MainActor @Sendable (Result<Void, Error>) -> Void

    private struct Request {
        let action: DraftPersistenceAction
        let completion: Completion
    }

    private let save: @Sendable (DraftSnapshot) throws -> Void
    private let delete: @Sendable (String) -> Void
    private let queue = DispatchQueue(
        label: "top.muds.mudsnote.draft-persistence",
        qos: .utility
    )
    private let lock = NSLock()
    private var pendingRequest: Request?
    private var isWorkerScheduled = false

    init(
        save: @escaping @Sendable (DraftSnapshot) throws -> Void,
        delete: @escaping @Sendable (String) -> Void
    ) {
        self.save = save
        self.delete = delete
    }

    func enqueue(
        _ action: DraftPersistenceAction,
        completion: @escaping Completion
    ) {
        lock.lock()
        pendingRequest = Request(action: action, completion: completion)
        let shouldScheduleWorker = !isWorkerScheduled
        isWorkerScheduled = true
        lock.unlock()

        guard shouldScheduleWorker else { return }
        queue.async { [weak self] in
            self?.drainPendingRequests()
        }
    }

    func flush(_ action: DraftPersistenceAction) throws {
        lock.lock()
        pendingRequest = nil
        lock.unlock()

        var result: Result<Void, Error> = .success(())
        queue.sync {
            result = Result {
                try perform(action)
            }
        }
        try result.get()
    }

    func waitUntilIdle() {
        queue.sync {}
    }

    private func drainPendingRequests() {
        while true {
            lock.lock()
            guard let request = pendingRequest else {
                isWorkerScheduled = false
                lock.unlock()
                return
            }
            pendingRequest = nil
            lock.unlock()

            let result = Result {
                try perform(request.action)
            }
            Task { @MainActor in
                request.completion(result)
            }
        }
    }

    private func perform(_ action: DraftPersistenceAction) throws {
        switch action {
        case .save(let snapshot):
            try save(snapshot)
        case .delete(let id):
            delete(id)
        }
    }
}
