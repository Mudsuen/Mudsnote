import Foundation

/// A note reference and its editable destination in the original Markdown.
/// Ranges use UTF-16 offsets, matching NSString and the native editors.
struct MarkdownNoteReference: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case markdown, wiki }

    let kind: Kind
    /// Markdown escapes are decoded; percent escapes and fragments are preserved.
    let destination: String
    /// Excludes angle brackets, a Markdown title, and a Wiki display alias.
    let destinationRange: NSRange
    let sourceRange: NSRange
}

enum MarkdownNoteReferenceParser {
    static func references(
        in markdown: String,
        cancellationCheck: @Sendable () -> Bool = { false }
    ) -> [MarkdownNoteReference] {
        guard !cancellationCheck() else { return [] }
        let units = Array(markdown.utf16)
        let ignored = codeMask(in: units)
        var result: [MarkdownNoteReference] = []
        var index = 0
        while index < units.count {
            if index.isMultiple(of: 256), cancellationCheck() { return [] }
            if ignored[index] { index += 1; continue }
            if units[index] == 92 { index += 2; continue } // Escaped punctuation.
            guard units[index] == 91 else { index += 1; continue }
            let isImage = index > 0 && units[index - 1] == 33 && !isEscaped(index - 1, in: units)
            let reference: MarkdownNoteReference?
            if index + 1 < units.count, units[index + 1] == 91 {
                reference = wikiReference(at: index, in: units, ignored: ignored)
            } else {
                reference = markdownReference(at: index, in: units, ignored: ignored)
            }
            if let reference {
                if !isImage { result.append(reference) }
                index = NSMaxRange(reference.sourceRange)
            } else {
                index += 1
            }
        }
        return cancellationCheck() ? [] : result
    }

    private static func wikiReference(
        at start: Int, in units: [UInt16], ignored: [Bool]
    ) -> MarkdownNoteReference? {
        var index = start + 2
        var alias: Int?
        while index + 1 < units.count {
            if ignored[index] || isNewline(units[index]) { return nil }
            if units[index] == 92 { index += 2; continue }
            if units[index] == 124, alias == nil { alias = index }
            if units[index] == 93, units[index + 1] == 93 {
                return reference(
                    kind: .wiki, source: start..<(index + 2),
                    destination: (start + 2)..<(alias ?? index), in: units
                )
            }
            index += 1
        }
        return nil
    }

    private static func markdownReference(
        at start: Int, in units: [UInt16], ignored: [Bool]
    ) -> MarkdownNoteReference? {
        var index = start + 1
        var labelDepth = 1
        while index < units.count {
            if ignored[index] { index += 1; continue }
            if units[index] == 92 { index += 2; continue }
            if units[index] == 91 { labelDepth += 1 }
            if units[index] == 93 { labelDepth -= 1 }
            if labelDepth == 0 { break }
            index += 1
        }
        guard index + 1 < units.count, units[index + 1] == 40 else { return nil }
        index += 2
        while index < units.count, isWhitespace(units[index]) { index += 1 }
        guard index < units.count else { return nil }
        let destinationStart: Int
        let destinationEnd: Int
        if units[index] == 60 {
            destinationStart = index + 1
            index += 1
            while index < units.count, units[index] != 62 {
                if isNewline(units[index]) { return nil }
                if units[index] == 92 { index += 2 } else { index += 1 }
            }
            guard index < units.count else { return nil }
            destinationEnd = index
            index += 1
            while index < units.count, isWhitespace(units[index]) { index += 1 }
            if index < units.count, units[index] == 34 || units[index] == 39 {
                guard let end = quotedEnd(at: index, in: units) else { return nil }
                index = end + 1
                while index < units.count, isWhitespace(units[index]) { index += 1 }
            }
            guard index < units.count, units[index] == 41 else { return nil }
        } else {
            destinationStart = index
            var depth = 0
            var titleStart: Int?
            while index < units.count {
                if isNewline(units[index]) { return nil }
                if units[index] == 92 { index += 2; continue }
                if depth == 0, index > destinationStart, isWhitespace(units[index - 1]),
                   units[index] == 34 || units[index] == 39,
                   let end = quotedEnd(at: index, in: units) {
                    var after = end + 1
                    while after < units.count, isWhitespace(units[after]) { after += 1 }
                    if after < units.count, units[after] == 41 {
                        titleStart = index
                        index = after
                        break
                    }
                    index = end + 1
                    continue
                }
                if units[index] == 40 { depth += 1 }
                if units[index] == 41 {
                    if depth == 0 { break }
                    depth -= 1
                }
                index += 1
            }
            guard index < units.count, units[index] == 41 else { return nil }
            destinationEnd = titleStart ?? index
        }
        return reference(
            kind: .markdown, source: start..<(index + 1),
            destination: destinationStart..<destinationEnd, in: units
        )
    }

    private static func reference(
        kind: MarkdownNoteReference.Kind, source: Range<Int>,
        destination: Range<Int>, in units: [UInt16]
    ) -> MarkdownNoteReference? {
        var start = destination.lowerBound
        var end = destination.upperBound
        while start < end, isWhitespace(units[start]) { start += 1 }
        while end > start, isWhitespace(units[end - 1]) { end -= 1 }
        guard start < end else { return nil }
        var decoded: [UInt16] = []
        var index = start
        while index < end {
            if units[index] == 92, index + 1 < end, isASCIIPunctuation(units[index + 1]) {
                index += 1
            }
            decoded.append(units[index])
            index += 1
        }
        return MarkdownNoteReference(
            kind: kind, destination: String(decoding: decoded, as: UTF16.self),
            destinationRange: NSRange(location: start, length: end - start),
            sourceRange: NSRange(location: source.lowerBound, length: source.count)
        )
    }

    private static func codeMask(in units: [UInt16]) -> [Bool] {
        var ignored = Array(repeating: false, count: units.count)
        var fence: (marker: UInt16, length: Int)?
        var lineStart = 0
        while lineStart < units.count {
            var lineEnd = lineStart
            while lineEnd < units.count, !isNewline(units[lineEnd]) { lineEnd += 1 }
            var content = lineStart
            while content < lineEnd, units[content] == 32, content - lineStart < 4 { content += 1 }
            var runEnd = content
            if content - lineStart <= 3, content < lineEnd,
               units[content] == 96 || units[content] == 126 {
                while runEnd < lineEnd, units[runEnd] == units[content] { runEnd += 1 }
            }
            let runLength = runEnd - content
            let nextLine = lineEnd < units.count ? lineEnd + 1 : lineEnd
            if let active = fence {
                for index in lineStart..<nextLine { ignored[index] = true }
                if runLength >= active.length, units[content] == active.marker,
                   units[runEnd..<lineEnd].allSatisfy({ $0 == 32 || $0 == 9 || $0 == 13 }) {
                    fence = nil
                }
            } else if runLength >= 3,
                      units[content] != 96 || !units[runEnd..<lineEnd].contains(96) {
                fence = (units[content], runLength)
                for index in lineStart..<nextLine { ignored[index] = true }
            }
            lineStart = nextLine
        }
        var index = 0
        while index < units.count {
            if ignored[index] || units[index] != 96 || isEscaped(index, in: units) {
                index += 1
                continue
            }
            let start = index
            while index < units.count, units[index] == 96 { index += 1 }
            let length = index - start
            var search = index
            var closing: Int?
            while search < units.count, !ignored[search] {
                if units[search] != 96 { search += 1; continue }
                let runStart = search
                while search < units.count, units[search] == 96 { search += 1 }
                if search - runStart == length { closing = search; break }
            }
            if let closing {
                for position in start..<closing { ignored[position] = true }
                index = closing
            }
        }
        return ignored
    }

    private static func quotedEnd(at start: Int, in units: [UInt16]) -> Int? {
        var index = start + 1
        while index < units.count, !isNewline(units[index]) {
            if units[index] == 92 { index += 2; continue }
            if units[index] == units[start] { return index }
            index += 1
        }
        return nil
    }

    private static func isEscaped(_ index: Int, in units: [UInt16]) -> Bool {
        var preceding = index
        while preceding > 0, units[preceding - 1] == 92 { preceding -= 1 }
        return (index - preceding) % 2 == 1
    }

    private static func isWhitespace(_ unit: UInt16) -> Bool { unit == 32 || unit == 9 || isNewline(unit) }
    private static func isNewline(_ unit: UInt16) -> Bool { unit == 10 || unit == 13 }
    private static func isASCIIPunctuation(_ unit: UInt16) -> Bool {
        (33...47).contains(unit) || (58...64).contains(unit) || (91...96).contains(unit) || (123...126).contains(unit)
    }
}
