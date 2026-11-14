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

    init(noteStore: NoteStore, limit: Int) {
        self.noteStore = noteStore
        self.limit = limit
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
        let requestedRoots = roots ?? noteStore.knownSearchRoots()
        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            if delay > .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }

            guard let session = noteStore.makeSearchSession(
                roots: requestedRoots, cancellationCheck: { Task.isCancelled }) else { return }
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
                self.searchTask = nil
                completion(payload)
            }
        }
    }

    func cancel() {
        generation += 1
        searchTask?.cancel()
        searchTask = nil
    }

    func waitForCurrentSearchForTesting() async {
        await searchTask?.value
    }
}
