import CryptoKit
import Foundation

struct LibraryDocumentRevision: Equatable, Sendable {
    let standardizedPath: String
    let fileResourceIdentifier: String?
    let contentModificationDate: Date?
    let fileSize: Int?
    let contentDigest: SHA256.Digest

    static func read(at url: URL) throws -> LibraryDocumentRevision {
        let standardizedURL = url.standardizedFileURL
        var lastRead: LibraryDocumentRevision?

        for _ in 0..<2 {
            let before = try metadata(at: standardizedURL)
            let data = try Data(contentsOf: standardizedURL, options: .mappedIfSafe)
            let after = try metadata(at: standardizedURL)
            let revision = LibraryDocumentRevision(
                standardizedPath: standardizedURL.path,
                fileResourceIdentifier: after.fileResourceIdentifier,
                contentModificationDate: after.contentModificationDate,
                fileSize: after.fileSize,
                contentDigest: SHA256.hash(data: data)
            )
            lastRead = revision

            if before == after {
                return revision
            }
        }

        throw LibraryDocumentRevisionError.changedWhileReading(lastRead?.standardizedPath ?? standardizedURL.path)
    }

    func hasSameContent(as other: LibraryDocumentRevision) -> Bool {
        contentDigest == other.contentDigest
    }

    private static func metadata(at url: URL) throws -> Metadata {
        let values = try url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileResourceIdentifierKey,
            .fileSizeKey
        ])
        return Metadata(
            fileResourceIdentifier: values.fileResourceIdentifier.map(String.init(describing:)),
            contentModificationDate: values.contentModificationDate,
            fileSize: values.fileSize
        )
    }

    private struct Metadata: Equatable {
        let fileResourceIdentifier: String?
        let contentModificationDate: Date?
        let fileSize: Int?
    }
}

enum LibraryDocumentRevisionError: LocalizedError {
    case changedWhileReading(String)

    var errorDescription: String? {
        switch self {
        case .changedWhileReading(let path):
            return "\(URL(fileURLWithPath: path).lastPathComponent) 在检查期间再次发生变化，请稍后重试。"
        }
    }
}
