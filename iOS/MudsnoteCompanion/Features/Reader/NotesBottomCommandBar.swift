import SwiftUI
import ImageIO
import UIKit

struct NotesBottomCommandBar: ToolbarContent {
    @Binding var searchText: String
    @Binding var searchFocused: Bool
    var voiceInput: () -> Void
    var newNote: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            DefaultToolbarItem(kind: .search, placement: .bottomBar)

            ToolbarSpacer(.fixed, placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                NotesVoiceInputButton(action: voiceInput)
            }

            ToolbarSpacer(.fixed, placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                Button(action: newNote) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(MudsnoteColors.text)
                        .frame(width: 46, height: 46)
                        .background(Color.clear, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .tint(MudsnoteColors.text)
                .accessibilityLabel("Quick note")
                .accessibilityIdentifier("new-note-button")
            }
        } else {
            ToolbarItem(placement: .bottomBar) {
                NotesToolbarSearchField(
                    searchText: $searchText,
                    searchFocused: $searchFocused,
                    drawsFallbackBackground: true
                )
            }

            ToolbarItem(placement: .bottomBar) {
                NotesVoiceInputButton(action: voiceInput)
            }

            ToolbarItem(placement: .bottomBar) {
                Button(action: newNote) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(MudsnoteColors.text)
                        .frame(width: 46, height: 46)
                        .background(Color.clear, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .tint(MudsnoteColors.text)
                .accessibilityLabel("Quick note")
                .accessibilityIdentifier("new-note-button")
            }
        }
    }
}

struct NotesVoiceInputButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(MudsnoteColors.text)
                .frame(width: 46, height: 46)
                .background(Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .tint(MudsnoteColors.text)
        .accessibilityLabel("Quick recording")
        .accessibilityHint("Opens quick capture and starts recording")
        .accessibilityIdentifier("voice-input-button")
    }
}

extension View {
    @ViewBuilder
    func notesNativeToolbarSearch(
        text: Binding<String>,
        isPresented: Binding<Bool>
    ) -> some View {
        if #available(iOS 26.0, *) {
            searchable(
                text: text,
                isPresented: isPresented,
                placement: .toolbar,
                prompt: Text("Search")
            )
        } else {
            self
        }
    }
}

struct NotesToolbarSearchField: View {
    @Binding var searchText: String
    @Binding var searchFocused: Bool
    var drawsFallbackBackground: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            NativeToolbarSearchField(
                text: $searchText,
                isFocused: $searchFocused
            )
            .accessibilityIdentifier("library-search-field")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("clear-library-search")
            }
        }
        .foregroundStyle(MudsnoteColors.text)
        .padding(.horizontal, 12)
        .frame(minWidth: 190, idealWidth: 226)
        .frame(height: 38)
        .background {
            if drawsFallbackBackground {
                Capsule().fill(.regularMaterial)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct NativeToolbarSearchField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.placeholder = String(localized: "Search")
        field.font = .preferredFont(forTextStyle: .body)
        field.textColor = .label
        field.tintColor = UIColor(MudsnoteColors.primary)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .search
        field.accessibilityIdentifier = "library-search-field"
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text {
            field.text = text
        }
        let focusRequestChanged = context.coordinator.lastRequestedFocus != isFocused
        context.coordinator.lastRequestedFocus = isFocused
        if isFocused, !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        } else if focusRequestChanged, !isFocused, field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NativeToolbarSearchField
        var lastRequestedFocus: Bool?

        init(parent: NativeToolbarSearchField) {
            self.parent = parent
        }

        @objc func textDidChange(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
