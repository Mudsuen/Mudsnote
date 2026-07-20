import Foundation

enum AuthorizedLibraryPath {
    static func resolve(
        _ relativePath: String,
        within root: URL,
        constrainedTo directory: String? = nil
    ) -> URL? {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return nil }
        let standardizedRoot = root.standardizedFileURL
        let candidate = root
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        guard candidate.path.hasPrefix(standardizedRoot.path + "/") else { return nil }
        guard !containsSymbolicLink(relativePath, within: standardizedRoot) else { return nil }
        if let directory {
            let allowedRoot = root
                .appendingPathComponent(directory, isDirectory: true)
                .standardizedFileURL
            guard candidate.path.hasPrefix(allowedRoot.path + "/") else { return nil }
        }
        return candidate
    }

    private static func containsSymbolicLink(_ relativePath: String, within root: URL) -> Bool {
        var current = root
        for component in relativePath.split(separator: "/") {
            current.appendPathComponent(String(component))
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: current.path)) != nil {
                return true
            }
        }
        return false
    }
}
