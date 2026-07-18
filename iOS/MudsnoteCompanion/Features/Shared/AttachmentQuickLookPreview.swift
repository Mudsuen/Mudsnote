import QuickLook
import SwiftUI

struct AttachmentQuickLookPreview: UIViewControllerRepresentable {
    let preview: PreparedAttachmentPreview
    let onDismiss: () -> Void
    let onSave: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> HostController {
        let controller = HostController()
        controller.coordinator = context.coordinator
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ host: HostController, context: Context) {
        context.coordinator.parent = self
        host.coordinator = context.coordinator
        host.previewController?.reloadData()
    }

    final class HostController: UIViewController {
        weak var coordinator: Coordinator?
        weak var previewController: QLPreviewController?
        weak var presentedNavigationController: UINavigationController?
        private var hasPresentedPreview = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !hasPresentedPreview, let coordinator else { return }
            hasPresentedPreview = true

            let previewController = QLPreviewController()
            previewController.dataSource = coordinator
            previewController.delegate = coordinator
            let closeButton = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: coordinator,
                action: #selector(Coordinator.closePreview)
            )
            closeButton.accessibilityIdentifier = "attachment-preview-done"
            closeButton.accessibilityLabel = String(localized: "Done")
            previewController.navigationItem.leftBarButtonItem = closeButton
            let navigationController = UINavigationController(
                rootViewController: previewController
            )
            navigationController.modalPresentationStyle = .fullScreen
            self.previewController = previewController
            presentedNavigationController = navigationController
            coordinator.navigationController = navigationController
            present(navigationController, animated: false)
        }
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        var parent: AttachmentQuickLookPreview
        weak var navigationController: UINavigationController?
        private var editedURL: URL?
        private var hasFinished = false
        private var hasScheduledFinish = false

        init(parent: AttachmentQuickLookPreview) {
            self.parent = parent
        }

        @objc func closePreview() {
            guard !hasFinished else { return }
            navigationController?.dismiss(animated: true) { [weak self] in
                self?.scheduleFinish()
            }
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> any QLPreviewItem {
            parent.preview.url as NSURL
        }

        func previewController(
            _ controller: QLPreviewController,
            editingModeFor previewItem: any QLPreviewItem
        ) -> QLPreviewItemEditingMode {
            parent.preview.isPDF ? .updateContents : .disabled
        }

        func previewController(
            _ controller: QLPreviewController,
            didUpdateContentsOf previewItem: any QLPreviewItem
        ) {
            editedURL = parent.preview.url
        }

        func previewController(
            _ controller: QLPreviewController,
            didSaveEditedCopyOf previewItem: any QLPreviewItem,
            at modifiedContentsURL: URL
        ) {
            editedURL = modifiedContentsURL
        }

        func previewControllerDidDismiss(_ controller: QLPreviewController) {
            scheduleFinish()
        }

        private func scheduleFinish() {
            guard !hasFinished, !hasScheduledFinish else { return }
            hasScheduledFinish = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(750))
                self?.finishPreview()
            }
        }

        private func finishPreview() {
            guard !hasFinished else { return }
            hasFinished = true
            if parent.preview.isPDF {
                parent.onSave(editedURL ?? parent.preview.url)
            }
            parent.onDismiss()
        }
    }
}
