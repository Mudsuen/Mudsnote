import SwiftUI
import AVFoundation
import AVKit
import PencilKit
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

struct MarkdownLinkEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let draft: MarkdownLinkDraft
    let notes: [RecentMarkdownFile]
    let sourceRelativePath: String
    let onApply: (String, String) -> Void
    let onRemove: (() -> Void)?
    @State private var name: String
    @State private var destination: String
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case destination
    }

    init(
        draft: MarkdownLinkDraft,
        notes: [RecentMarkdownFile],
        sourceRelativePath: String,
        onApply: @escaping (String, String) -> Void,
        onRemove: (() -> Void)?
    ) {
        self.draft = draft
        self.notes = notes
        self.sourceRelativePath = sourceRelativePath
        self.onApply = onApply
        self.onRemove = onRemove
        _name = State(initialValue: draft.label)
        _destination = State(initialValue: draft.destination)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($focusedField, equals: .name)
                        .accessibilityIdentifier("markdown-link-name")
                    TextField("Link", text: $destination)
                        .focused($focusedField, equals: .destination)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("markdown-link-destination")
                }

                if !notes.isEmpty {
                    Section {
                        NavigationLink {
                            MarkdownNoteLinkPicker(
                                notes: notes,
                                selectedDestination: destination,
                                sourceRelativePath: sourceRelativePath
                            ) { note in
                                guard let relativeDestination = MarkdownNoteLink.relativeDestination(
                                    from: sourceRelativePath,
                                    to: note.relativePath
                                ) else { return }
                                destination = relativeDestination
                                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    name = note.title
                                }
                            }
                        } label: {
                            Label("Link to Note", systemImage: "note.text.badge.plus")
                        }
                        .accessibilityIdentifier("choose-note-link")
                    }
                }

                if let onRemove {
                    Section {
                        Button("Remove Link", role: .destructive) {
                            onRemove()
                        }
                        .accessibilityIdentifier("remove-markdown-link")
                    }
                }
            }
            .navigationTitle(draft.isExisting ? "Edit Link" : "Add Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.isExisting ? "Done" : "Add") {
                        onApply(name, destination)
                    }
                    .fontWeight(.semibold)
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .accessibilityIdentifier("apply-markdown-link")
                }
            }
        }
        .onAppear {
            focusedField = name.isEmpty ? .name : .destination
        }
    }
}

struct MarkdownNoteLinkPicker: View {
    @Environment(\.dismiss) private var dismiss
    let notes: [RecentMarkdownFile]
    let selectedDestination: String
    let sourceRelativePath: String
    let onSelect: (RecentMarkdownFile) -> Void
    @State private var query = ""

    private var filteredNotes: [RecentMarkdownFile] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return notes }
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(term)
                || $0.relativePath.localizedCaseInsensitiveContains(term)
        }
    }

    var body: some View {
        List(filteredNotes) { note in
            Button {
                onSelect(note)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "note.text")
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.title)
                            .foregroundStyle(MudsnoteColors.text)
                        Text(note.relativePath)
                            .font(.caption)
                            .foregroundStyle(MudsnoteColors.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                    if isSelected(note) {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("note-link-candidate-\(note.relativePath)")
        }
        .overlay {
            if filteredNotes.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Link to Note")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search Notes")
    }

    private func isSelected(_ note: RecentMarkdownFile) -> Bool {
        MarkdownNoteLink.resolvedRelativePath(
            for: selectedDestination,
            from: sourceRelativePath
        ) == note.relativePath
    }
}

struct MarkdownTagSuggestions: View {
    let tags: [String]
    let knownTags: Set<String>
    let select: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "number")
                Text("Tags")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("Space or Return to confirm")
                    .font(.caption2)
            }
            .foregroundStyle(MudsnoteColors.muted)
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 5)

            ForEach(tags, id: \.self) { tag in
                Button {
                    select(tag)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "number.circle.fill")
                            .font(.title3)
                            .foregroundStyle(MudsnoteColors.primary)
                        Text(tag)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MudsnoteColors.text)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if !knownTags.contains(MarkdownTagSyntax.key(tag)) {
                            Text("New")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(MudsnoteColors.primary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    MudsnoteColors.primary.opacity(0.12),
                                    in: Capsule()
                                )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tag-suggestion-\(tag)")
            }
        }
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(MudsnoteColors.line, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
    }
}

struct MarkdownNoteMentionSuggestions: View {
    let notes: [RecentMarkdownFile]
    let select: (RecentMarkdownFile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(notes) { note in
                Button {
                    select(note)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "note.text")
                            .foregroundStyle(MudsnoteColors.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MudsnoteColors.text)
                                .lineLimit(1)
                            Text(note.relativePath)
                                .font(.caption)
                                .foregroundStyle(MudsnoteColors.muted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("note-mention-\(note.relativePath)")
            }
        }
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(MudsnoteColors.line, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }
}
