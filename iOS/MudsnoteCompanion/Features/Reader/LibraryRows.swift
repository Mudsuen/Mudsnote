import SwiftUI
import ImageIO
import UIKit

struct NotesSectionHeader: View {
    var title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(MudsnoteColors.text)
            Spacer()
        }
        .padding(.horizontal, 2)
    }
}

struct NotesFolderRow: View {
    var title: String
    var systemImage: String
    var iconTint: Color = MudsnoteColors.text
    var count: Int?
    var showsChevron = true
    var trailingAccessoryWidth: CGFloat = 0
    var indentation: CGFloat = 0
    var isSelected = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(iconTint)
                .frame(width: 36, height: 36)
                .background(iconTint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))

            Text(title)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(MudsnoteColors.text)
                .layoutPriority(1)

            Spacer()

            if let count {
                Text("\(count)")
                    .font(.system(.subheadline, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(MudsnoteColors.muted)
                    .frame(minWidth: 28, alignment: .trailing)
                    .fixedSize()
                    .accessibilityIdentifier("folder-count-\(title)")
            }

            ZStack(alignment: .trailing) {
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MudsnoteColors.muted.opacity(0.7))
                }
            }
            .frame(width: max(28, trailingAccessoryWidth), height: 44, alignment: .trailing)
        }
        .padding(.leading, 10 + indentation)
        .padding(.trailing, 10)
        .frame(height: 50)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MudsnoteColors.primary.opacity(0.14))
            }
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(MudsnoteColors.primary)
                    .frame(width: 3, height: 28)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 58)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NotesCloneColors.separator)
                .frame(height: 1)
                .padding(.leading, 72 + indentation)
        }
    }
}

struct LibraryUtilityButton: View {
    var systemImage: String
    var count: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemImage)
                .font(.system(size: 21, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(MudsnoteColors.text)
                .frame(width: 38, height: 38)
                .background(
                    MudsnoteColors.text.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 11)
                )

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(MudsnoteColors.canvas)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(MudsnoteColors.text, in: Capsule())
                    .offset(x: 6, y: -5)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .contentShape(Rectangle())
    }
}

struct TagDirectoryRow: View {
    var tag: TagSummary

    private var displayName: String {
        tag.name.hasPrefix("#") ? String(tag.name.dropFirst()) : tag.name
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "number")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(NotesCloneColors.folderYellow)
                .frame(width: 34, height: 34)
                .background(
                    NotesCloneColors.folderYellow.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            Text(displayName)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(MudsnoteColors.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text("\(tag.count)")
                .font(.system(.subheadline, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(MudsnoteColors.muted)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MudsnoteColors.muted.opacity(0.7))
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NotesCloneColors.separator)
                .frame(height: 1)
                .padding(.leading, 48)
        }
    }
}

struct NoteTagPickerView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var isAdding = false

    var noteText: String
    var existingTags: [String]
    var addTag: (String) async -> Bool

    private var rankedTags: [TagSummary] {
        TagSuggestionRanker.rank(
            query: input,
            noteText: noteText,
            summaries: appModel.tagSummaries
        )
    }

    private var existingTagKeys: Set<String> {
        Set(existingTags.map(MarkdownTagSyntax.key))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("New Tag", text: $input)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { submitInput() }
                        .accessibilityIdentifier("new-tag-field")
                } footer: {
                    Text("Press Space or Return to add a new tag.")
                }

                Section("Recommended") {
                    ForEach(rankedTags) { tag in
                        Button {
                            submit(tag.name)
                        } label: {
                            HStack {
                                Text(tag.name)
                                Spacer()
                                Text("\(tag.count)")
                                    .foregroundStyle(MudsnoteColors.muted)
                                if existingTagKeys.contains(MarkdownTagSyntax.key(tag.name)) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(MudsnoteColors.primary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            isAdding
                                || existingTagKeys.contains(MarkdownTagSyntax.key(tag.name))
                        )
                        .accessibilityIdentifier("tag-suggestion-\(tag.name)")
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: input) { _, value in
                guard value.last?.isWhitespace == true else { return }
                input = value.trimmingCharacters(in: .whitespacesAndNewlines)
                submitInput()
            }
        }
    }

    private func submitInput() {
        submit(input)
    }

    private func submit(_ value: String) {
        guard !isAdding,
              let tag = MarkdownTagSyntax.normalizedTag(value) else { return }
        isAdding = true
        Task {
            let succeeded = await addTag(tag)
            isAdding = false
            if succeeded { dismiss() }
        }
    }
}

enum TagMatchMode: String, CaseIterable, Identifiable {
    case any
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: String(localized: "Any")
        case .all: String(localized: "All")
        }
    }
}

enum TagFilterState: Equatable {
    case inactive
    case included
    case excluded
}

struct TagSelectionFilter: Equatable {
    var included = Set<String>()
    var excluded = Set<String>()
    var matchMode = TagMatchMode.any

    var isEmpty: Bool { included.isEmpty && excluded.isEmpty }

    mutating func cycle(_ tag: String) {
        switch state(for: tag) {
        case .inactive:
            included.insert(tag)
        case .included:
            included.remove(tag)
            excluded.insert(tag)
        case .excluded:
            excluded.remove(tag)
        }
    }

    mutating func clear() {
        included.removeAll()
        excluded.removeAll()
    }

    func state(for tag: String) -> TagFilterState {
        if contains(tag, in: included) { return .included }
        if contains(tag, in: excluded) { return .excluded }
        return .inactive
    }

    func matches(tags: [String]) -> Bool {
        let candidateKeys = Set(tags.map(Self.key))
        guard !candidateKeys.isEmpty else { return false }
        let excludedKeys = Set(excluded.map(Self.key))
        guard candidateKeys.isDisjoint(with: excludedKeys) else { return false }

        let includedKeys = Set(included.map(Self.key))
        guard !includedKeys.isEmpty else { return true }
        switch matchMode {
        case .any:
            return !candidateKeys.isDisjoint(with: includedKeys)
        case .all:
            return includedKeys.isSubset(of: candidateKeys)
        }
    }

    private func contains(_ tag: String, in values: Set<String>) -> Bool {
        let key = Self.key(tag)
        return values.contains { Self.key($0) == key }
    }

    private static func key(_ tag: String) -> String {
        tag.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }
}

struct TagFilterChip: View {
    var title: String
    var state: TagFilterState

    var body: some View {
        HStack(spacing: 7) {
            if state != .inactive {
                Image(systemName: state == .included ? "checkmark" : "minus")
                    .font(.caption.weight(.bold))
            }
            Text(title)
                .strikethrough(state == .excluded)
        }
        .font(.system(.subheadline, design: .rounded, weight: .semibold))
        .foregroundStyle(state == .included ? Color.black : MudsnoteColors.text)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(chipBackground, in: Capsule())
        .overlay {
            Capsule().stroke(chipBorder, lineWidth: 1)
        }
    }

    private var chipBackground: Color {
        switch state {
        case .inactive: NotesCloneColors.chip
        case .included: NotesCloneColors.folderYellow
        case .excluded: MudsnoteColors.card
        }
    }

    private var chipBorder: Color {
        state == .inactive ? MudsnoteColors.line : NotesCloneColors.folderYellow.opacity(0.8)
    }
}
