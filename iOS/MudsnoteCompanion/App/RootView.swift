import SwiftUI

enum ReaderPresentationPolicy {
    static func detents(isEditing: Bool) -> Set<PresentationDetent> {
        isEditing ? [.large] : [.medium, .large]
    }
}

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isFolderImporterPresented = false
    @State private var readerDetent: PresentationDetent = .medium
    @State private var isReaderEditing = false

    private var usesFullReaderForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing-full-reader")
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            MudsnoteColors.canvas.ignoresSafeArea()

            Group {
                switch appModel.folderStatus {
                case .loading:
                    ProgressView("Opening Mudsnote…")
                        .tint(MudsnoteColors.primary)
                        .foregroundStyle(MudsnoteColors.muted)
                case .missing:
                    OnboardingFolderView {
                        isFolderImporterPresented = true
                    }
                case .ready:
                    tabShell
                case .error(let message):
                    FolderErrorView(
                        message: message,
                        chooseFolder: { isFolderImporterPresented = true },
                        forgetFolder: { appModel.forgetFolderAndChooseAgain() }
                    )
                }
            }

            if isHalfReaderPresented {
                MudsnoteColors.panel.opacity(0.96)
                    .frame(height: 14)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        appModel.selectedMemo = nil
                        appModel.selectedDocument = nil
                    }
                    .accessibilityElement()
                    .accessibilityLabel("Close note")
                    .accessibilityIdentifier("note-reader-background-dismiss")
            }

            if let toast = appModel.statusToast {
                StatusToastView(toast: toast)
                    .padding(.horizontal, MudsnoteSpacing.safeHorizontal)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(2))
                        if appModel.statusToast?.id == toast.id {
                            appModel.statusToast = nil
                        }
                    }
            }
        }
        .fileImporter(
            isPresented: $isFolderImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                appModel.selectFolder(url)
            }
        }
        .sheet(isPresented: $appModel.isCapturePresented) {
            CaptureConsoleView(initialRoute: appModel.captureRoute)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(MudsnoteColors.panel.opacity(0.96))
        }
        .sheet(item: $appModel.selectedMemo) { memo in
            MarkdownPreviewView(
                memo: memo,
                startsEditing: appModel.noteOpenMode == .edit,
                requestEditing: expandReaderForEditing,
                editingChanged: updateReaderEditing
            )
                .presentationDetents(readerDetents, selection: $readerDetent)
                .presentationContentInteraction(.scrolls)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
                .presentationBackground {
                    MudsnoteReaderSheetBackground()
                }
        }
        .sheet(item: $appModel.selectedDocument) { document in
            MarkdownPreviewView(
                document: document,
                startsEditing: appModel.noteOpenMode == .edit,
                requestEditing: expandReaderForEditing,
                editingChanged: updateReaderEditing
            )
                .presentationDetents(readerDetents, selection: $readerDetent)
                .presentationContentInteraction(.scrolls)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
                .presentationBackground {
                    MudsnoteReaderSheetBackground()
                }
        }
        .onChange(of: appModel.selectedMemo?.id) { _, id in
            if id != nil {
                readerDetent = usesFullReaderForUITests || appModel.noteOpenMode == .edit
                    ? .large
                    : .medium
                appModel.isReaderExpanded = readerDetent == .large
            } else {
                appModel.noteOpenMode = .read
                appModel.isReaderExpanded = false
                isReaderEditing = false
            }
        }
        .onChange(of: appModel.selectedDocument?.id) { _, id in
            if let document = appModel.selectedDocument, id != nil {
                readerDetent = usesFullReaderForUITests
                    || document.isNew
                    || appModel.noteOpenMode == .edit
                    ? .large
                    : .medium
                appModel.isReaderExpanded = readerDetent == .large
            } else {
                appModel.noteOpenMode = .read
                appModel.isReaderExpanded = false
                isReaderEditing = false
            }
        }
        .onChange(of: readerDetent) { _, detent in
            appModel.isReaderExpanded = detent == .large
        }
    }

    private var tabShell: some View {
        LibraryHomeView {
            isFolderImporterPresented = true
        }
    }

    private var isHalfReaderPresented: Bool {
        !appModel.isReaderExpanded
            && (appModel.selectedMemo != nil || appModel.selectedDocument != nil)
    }

    private var readerDetents: Set<PresentationDetent> {
        ReaderPresentationPolicy.detents(isEditing: isReaderEditing)
    }

    private func expandReaderForEditing() {
        appModel.noteOpenMode = .edit
        readerDetent = .large
        appModel.isReaderExpanded = true
    }

    private func updateReaderEditing(_ isEditing: Bool) {
        isReaderEditing = isEditing
        if isEditing {
            expandReaderForEditing()
        }
    }
}
