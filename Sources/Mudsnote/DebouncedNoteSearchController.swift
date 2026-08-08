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
            if let existingSession {
                session = existingSession
            } else {
                guard let builtSession = noteStore.makeSearchSession(
                    roots: noteStore.knownSearchRoots(),
                    cancellationCheck: { Task.isCancelled }
                ) else {
                    return
                }
                session = builtSession
            }
            guard !Task.isCancelled else { return }
            let results = session.searchNotes(
                query: query,
                limit: limit,
                cancellationCheck: { Task.isCancelled }
            )
            guard !Task.isCancelled else { return }
            let payload = DebouncedNoteSearchResults(
                query: query,
                results: results,
                searchRootCount: noteStore.knownSearchRoots().count
            )

            await MainActor.run {
                guard !Task.isCancelled,
                      let self,
                      self.generation == requestGeneration else {
                    return
                }
                self.searchSession = session
                self.searchTask = nil
                completion(payload)
            }
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
