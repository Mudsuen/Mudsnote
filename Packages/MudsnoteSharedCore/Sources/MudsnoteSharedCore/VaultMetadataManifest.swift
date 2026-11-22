import Foundation

/// Portable vault-level metadata stored at `<vault>/.mudsnote/metadata.json`
/// so pinned notes, folder ordering, and folder icons sync cleanly between macOS and iOS via iCloud Drive.
public struct VaultMetadataManifest: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let directoryName = ".mudsnote"
    public static let filename = "metadata.json"

    public var version: Int
    public var updatedAt: Date
    /// Vault-relative paths (POSIX `/` separators) of pinned Markdown notes.
    public var pinnedRelativePaths: [String]
    /// Vault-relative folder paths in preferred display order.
    public var folderOrder: [String]
    /// Mapping from vault-relative folder path to SF Symbol name.
    public var folderIcons: [String: String]

    public init(
        version: Int = VaultMetadataManifest.schemaVersion,
        updatedAt: Date = Date(),
        pinnedRelativePaths: [String] = [],
        folderOrder: [String] = [],
        folderIcons: [String: String] = [:]
    ) {
        self.version = version
        self.updatedAt = updatedAt
        self.pinnedRelativePaths = Self.deduplicated(pinnedRelativePaths)
        self.folderOrder = Self.deduplicated(folderOrder)
        self.folderIcons = folderIcons
    }

    public static func manifestURL(in vaultRoot: URL) -> URL {
        vaultRoot
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }

    public static func load(in vaultRoot: URL) -> VaultMetadataManifest? {
        let fileURL = manifestURL(in: vaultRoot)
        var coordinationError: NSError?
        var decoded: VaultMetadataManifest?
        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { coordinated in
            guard let data = try? Data(contentsOf: coordinated) else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decoded = try? decoder.decode(VaultMetadataManifest.self, from: data)
        }
        return decoded
    }

    public static func save(_ manifest: VaultMetadataManifest, in vaultRoot: URL) throws {
        let directoryURL = vaultRoot.appendingPathComponent(directoryName, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent(filename, isDirectory: false)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)

        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinationError) { coordinated in
            do {
                try data.write(to: coordinated, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let error = coordinationError ?? (writeError as NSError?) {
            throw error
        }
    }

    /// Merges remote and local pinned paths cleanly, preferring the newer manifest for ordering/icons.
    public func merged(with other: VaultMetadataManifest) -> VaultMetadataManifest {
        let newer = updatedAt >= other.updatedAt ? self : other
        let older = updatedAt >= other.updatedAt ? other : self
        var mergedIcons = older.folderIcons
        for (key, value) in newer.folderIcons {
            mergedIcons[key] = value
        }
        let mergedOrder = Self.deduplicated(newer.folderOrder + older.folderOrder)
        return VaultMetadataManifest(
            version: max(version, other.version),
            updatedAt: max(updatedAt, other.updatedAt),
            pinnedRelativePaths: newer.pinnedRelativePaths,
            folderOrder: mergedOrder,
            folderIcons: mergedIcons
        )
    }

    private static func deduplicated(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
