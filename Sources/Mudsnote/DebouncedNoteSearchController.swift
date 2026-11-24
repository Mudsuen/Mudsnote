import Foundation
import MudsnoteCore

struct DebouncedNoteSearchResults: Sendable {
    let query: String
    let results: [NoteSearchResult]
    let searchRootCount: Int
}

@MainActor
final class DebouncedNoteSearchController {
    static let defaultDelay = Duration.milliseconds(150)

    private let noteStore: NoteStore
    private let limit: Int
    private var searchTask: Task<Void, Never>?
    private var generation = 0
    private var cachedSession: (rootsKey: [String], revision: UInt64, session: NoteSearchSession)?

    init(noteStore: NoteStore, limit: Int) {
        self.noteStore = noteStore
        self.limit = limit
    }

    deinit {
        searchTask?.cancel()
    }

    func submit(
        query: String,
        roots: [URL]? = nil,
        filter: NoteSearchFilter = .all,
        delay: Duration = defaultDelay,
        onStart: () -> Void = {},
        completion: @escaping @MainActor (DebouncedNoteSearchResults) -> Void
    ) {
        generation += 1
        let requestGeneration = generation
        searchTask?.cancel()
        onStart()

        let noteStore = noteStore
        let limit = limit
        let requestedRoots = roots ?? noteStore.preferredDirectories
        let rootsKey = requestedRoots.map { $0.standardizedFileURL.path }
        let currentRevision = noteStore.currentSearchIndexRevision
        let reusableSession: NoteSearchSession?
        if let cached = cachedSession,
           cached.rootsKey == rootsKey,
           cached.revision == currentRevision {
            reusableSession = cached.session
        } else {
            reusableSession = nil
        }

        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            if delay > .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }

            let session: NoteSearchSession
            let sessionRevision: UInt64
            if let reusableSession {
                session = reusableSession
                sessionRevision = currentRevision
            } else {
                guard let built = noteStore.makeSearchSession(
                    roots: requestedRoots,
                    cancellationCheck: { Task.isCancelled }
                ) else { return }
                session = built
                sessionRevision = noteStore.currentSearchIndexRevision
            }
            guard !Task.isCancelled else { return }
            let results = session.searchNotes(
                query: query,
                limit: limit,
                filter: filter,
                cancellationCheck: { Task.isCancelled }
            )
            guard !Task.isCancelled else { return }
            let payload = DebouncedNoteSearchResults(
                query: query,
                results: results,
                searchRootCount: requestedRoots.count
            )

            await MainActor.run {
                guard !Task.isCancelled,
                      let self,
                      self.generation == requestGeneration else {
                    return
                }
                self.cachedSession = (rootsKey, sessionRevision, session)
                self.searchTask = nil
                completion(payload)
            }
        }
    }

    func cancel() {
        generation += 1
        searchTask?.cancel()
        searchTask = nil
        cachedSession = nil
    }

    func waitForCurrentSearchForTesting() async {
        await searchTask?.value
    }
}
