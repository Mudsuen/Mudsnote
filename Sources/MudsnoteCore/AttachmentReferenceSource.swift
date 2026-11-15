import Foundation

/// Resolution uses the original note location, while opening uses a real source
/// identity. A recovery/draft source must never open a later note at its old path.
public struct AttachmentReferenceSource: Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case note, draft, trash }
    public let resolutionURL: URL
    public let identityURL: URL
    public let kind: Kind
    public var openableNoteURL: URL? { kind == .note ? identityURL : nil }

    public init(resolutionURL: URL, identityURL: URL, kind: Kind) {
        self.resolutionURL = resolutionURL.standardizedFileURL
        self.identityURL = identityURL.standardizedFileURL
        self.kind = kind
    }
}

public struct ProtectedAttachmentReferenceSource: Sendable {
    public let source: AttachmentReferenceSource
    public let markdown: String
    public init(source: AttachmentReferenceSource, markdown: String) {
        self.source = source; self.markdown = markdown
    }
}
