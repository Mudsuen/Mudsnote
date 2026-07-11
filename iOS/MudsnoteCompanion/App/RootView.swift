import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isFolderImporterPresented = false

    var body: some View {
        ZStack(alignment: .bottom) {
            MudsnoteColors.canvas.ignoresSafeArea()

            Group {
                switch appModel.folderStatus {
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
                .presentationDetents([.fraction(0.32), .medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(MudsnoteColors.panel.opacity(0.96))
        }
        .sheet(item: $appModel.selectedMemo) { memo in
            MarkdownPreviewView(memo: memo)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(MudsnoteColors.panel)
        }
    }

    private var tabShell: some View {
        LibraryHomeView {
            isFolderImporterPresented = true
        }
    }
}
