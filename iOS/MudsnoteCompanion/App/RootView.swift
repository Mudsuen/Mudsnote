import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isFolderImporterPresented = false
    @State private var readerDetent: PresentationDetent = .medium

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
                startsEditing: appModel.noteOpenMode == .edit
            )
                .presentationDetents([.medium, .large], selection: $readerDetent)
                .presentationContentInteraction(.scrolls)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
                .presentationBackground(MudsnoteColors.panel)
        }
        .sheet(item: $appModel.selectedDocument) { document in
            MarkdownPreviewView(
                document: document,
                startsEditing: appModel.noteOpenMode == .edit
            )
                .presentationDetents([.medium, .large], selection: $readerDetent)
                .presentationContentInteraction(.scrolls)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
                .presentationBackground(MudsnoteColors.panel)
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
}
