import Foundation

public enum AIPromptBuilder {
    public static func prompt(for request: AIRequest) throws -> String {
        let input = request.inputMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw AIError.emptyInput }

        let scopeLine: String
        switch request.scope {
        case .selection: scopeLine = "Input scope: selected Markdown only."
        case .currentParagraph: scopeLine = "Input scope: current Markdown paragraph only."
        case .wholeNote: scopeLine = "Input scope: current note only."
        }

        let instruction: String
        switch request.actionID {
        case .summarize:
            instruction = """
            Summarize the following Markdown as 3 to 5 concise bullet points.
            Return only Markdown bullets.
            Preserve important names, dates, decisions, and tasks.
            Do not invent facts.
            """
        case .fix:
            instruction = """
            Fix spelling, grammar, and punctuation in the following Markdown.
            Do not change meaning, structure, links, code spans, hashtags, or task markers.
            Return only the corrected Markdown.
            """
        case .todos:
            instruction = """
            Extract concrete action items from the following Markdown.
            Return only Markdown task items using "- [ ]".
            Do not invent tasks.
            If there are no concrete action items, return "- [ ] Review notes".
            """
        }

        let titleLine = request.noteTitle
            .map { "Note title: \($0)" }
            ?? "Note title: unavailable"
        let userInstruction = request.userInstruction
            .map { "\nUser instruction: \($0)" }
            ?? ""

        return """
        You are a Markdown transformation command inside a local-first macOS notes app.
        \(scopeLine)
        \(titleLine)
        \(instruction)\(userInstruction)

        Markdown input:
        ---
        \(input)
        ---
        """
    }
}
