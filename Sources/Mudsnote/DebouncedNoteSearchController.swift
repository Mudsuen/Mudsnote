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
    private var searchSession: NoteSearchSession?
    private var searchTask: Task<Void, Never>?
    private var generation = 0

    init(noteStore: NoteStore, limit: Int) {
        self.noteStore = noteStore
        self.limit = limit
    }

    func submit(
        query: String,
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
        let existingSession = searchSession
        searchTask = Task { [weak self] in
            if delay > .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }

            let payload = await Task.detached(priority: .userInitiated) {
                let session = existingSession ?? noteStore.makeSearchSession()
                let results = session.searchNotes(query: query, limit: limit)
                let rootCount = noteStore.knownSearchRoots().count
                return (
                    session,
                    DebouncedNoteSearchResults(
                        query: query,
                        results: results,
                        searchRootCount: rootCount
                    )
                )
            }.value

            guard !Task.isCancelled,
                  let self,
                  self.generation == requestGeneration else {
                return
            }
            self.searchSession = payload.0
            self.searchTask = nil
            completion(payload.1)
        }
    }

    func cancel(invalidateSession: Bool = false) {
        generation += 1
        searchTask?.cancel()
        searchTask = nil
        if invalidateSession {
            searchSession = nil
        }
    }

    func waitForCurrentSearchForTesting() async {
        await searchTask?.value
    }
}
