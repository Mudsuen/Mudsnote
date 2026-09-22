import Foundation
import Testing
@testable import MudsnoteCore

struct MarkdownNoteReferenceParserTests {
    @Test
    func codeExamplesDoNotBecomeReferences() {
        let markdown = """
        [Actual](Actual.md)
        ```markdown
        [Fenced](Fenced.md)
        [[Fenced Wiki]]
        ```
        ~~~markdown
        [[Tilde Fence]]
        ~~~
        `[Inline](Inline.md)` and `[[Inline Wiki]]`
        ``a ` backtick and [[Long Inline]]``
        [[Actual Wiki|Displayed name]]
        """

        let references = MarkdownNoteReferenceParser.references(in: markdown)

        #expect(references.map(\.destination) == ["Actual.md", "Actual Wiki"])
        #expect(references.map(\.kind) == [.markdown, .wiki])
    }

    @Test
    func fencesRespectMarkerLengthAndUnclosedBlocks() {
        let markdown = """
          ````markdown
        ```
        [[Still fenced]]
          ````
        [[Visible]]
        ~~~
        [[Unclosed fence]]
        """

        #expect(MarkdownNoteReferenceParser.references(in: markdown).map(\.destination) == ["Visible"])
        #expect(MarkdownNoteReferenceParser.references(in: "Unmatched ` then [[Visible]]").map(\.destination) == ["Visible"])
    }

    @Test
    func ignoresImagesAndEscapedLinkConstructs() {
        let markdown = #"\[Escaped](Escaped.md) ![Image](Image.md) ![[Embedded]] \[[Escaped Wiki]] [[Visible]]"#

        #expect(MarkdownNoteReferenceParser.references(in: markdown).map(\.destination) == ["Visible"])
    }

    @Test
    func destinationsHaveExactUTF16RangesForSafeRewriting() throws {
        let markdown = #"🙂 [Plan \] details](<../笔记%20A.md#小节> "A title") [[ Folder/笔记%20B.md#section |可见别名]]"#
        let references = MarkdownNoteReferenceParser.references(in: markdown)
        #expect(references.count == 2)
        let first = try #require(references.first)
        let last = try #require(references.last)
        let text = markdown as NSString

        #expect(first.destination == "../笔记%20A.md#小节")
        #expect(text.substring(with: first.destinationRange) == "../笔记%20A.md#小节")
        #expect(text.substring(with: first.sourceRange) == #"[Plan \] details](<../笔记%20A.md#小节> "A title")"#)
        #expect(last.destination == "Folder/笔记%20B.md#section")
        #expect(text.substring(with: last.destinationRange) == "Folder/笔记%20B.md#section")

        let rewritten = NSMutableString(string: markdown)
        rewritten.replaceCharacters(in: last.destinationRange, with: "Moved/Note.md#section")
        rewritten.replaceCharacters(in: first.destinationRange, with: "../Moved.md#小节")
        #expect(rewritten as String == #"🙂 [Plan \] details](<../Moved.md#小节> "A title") [[ Moved/Note.md#section |可见别名]]"#)
    }

    @Test
    func parsesSpacesBalancedParenthesesQuotedTitlesAndEscapes() {
        let markdown = #"[One](Docs/Plan (v2).md#Part%201 "Example ) title") [Two](Some\(thing\).md 'Title') [Three](<Folder/Name with spaces.md#Part 2>)"#

        let references = MarkdownNoteReferenceParser.references(in: markdown)

        #expect(references.map(\.destination) == [
            "Docs/Plan (v2).md#Part%201", "Some(thing).md", "Folder/Name with spaces.md#Part 2"
        ])
        #expect((markdown as NSString).substring(with: references[1].destinationRange) == #"Some\(thing\).md"#)
    }

    @Test
    func cancellationPublishesNoReferences() {
        #expect(MarkdownNoteReferenceParser.references(in: "[[Target]]", cancellationCheck: { true }).isEmpty)
    }

    @Test
    func generatedEscapedTitleRoundTripsThroughBothRelationAPIs() throws {
        try withStore { store in
            let target = try store.saveNewNote(title: "Plan ] Details", body: "Target")
            let source = try store.saveNewNote(title: "Source", body: "Source")
            let link = store.markdownKnowledgeLink(from: source, to: target, title: "Plan ] Details")
            _ = try store.updateNoteInPlace(at: source, title: "Source", body: link)

            #expect(store.knowledgeRelations(for: source).outgoing.map(\.url) == [target])
            #expect(store.linkRelations(for: source).outgoing.map(\.url) == [target])
            #expect(store.knowledgeRelations(for: target).incoming.map(\.url) == [source])
        }
    }

    @Test
    func codeExamplesCreateNeitherBacklinksNorGraphEdges() throws {
        try withStore { store in
            let target = try store.saveNewNote(title: "Target", body: "Target")
            let source = try store.saveNewNote(title: "Source", body: "Source")
            let link = store.markdownKnowledgeLink(from: source, to: target, title: "Target")
            let wiki = "[[\(target.deletingPathExtension().lastPathComponent)]]"
            let codeExamples = "```markdown\n\(link)\n\(wiki)\n```\n\n`\(link)` and `\(wiki)`"
            _ = try store.updateNoteInPlace(at: source, title: "Source", body: codeExamples)

            #expect(store.knowledgeRelations(for: source).outgoing.isEmpty)
            #expect(store.knowledgeRelations(for: target).incoming.isEmpty)
            #expect(store.linkRelations(for: source).outgoing.isEmpty)
            #expect(store.linkRelations(for: target).incoming.isEmpty)
            #expect(store.knowledgeGraphSnapshot(scope: .global).edges.isEmpty)
        }
    }

    private func withStore(_ operation: (NoteStore) throws -> Void) throws {
        let suite = "mudsnote.reference-parser-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-reference-parser-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let store = NoteStore(
            defaults: defaults, legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("Support", isDirectory: true)
        )
        let notes = root.appendingPathComponent("Notes", isDirectory: true)
        store.configurePreferredDirectories([notes], defaultDirectory: notes)
        try operation(store)
    }
}
