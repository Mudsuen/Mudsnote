import AppKit
@preconcurrency import QuickLookUI

@MainActor
final class AttachmentQuickLookController: NSObject, @preconcurrency QLPreviewPanelDataSource {
    private var previewItem: NSURL?

    var previewedURL: URL? {
        previewItem as URL?
    }

    @discardableResult
    func preview(_ url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardizedURL.path),
              let panel = QLPreviewPanel.shared() else {
            return false
        }

        previewItem = standardizedURL as NSURL
        panel.makeKeyAndOrderFront(nil)
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.refreshCurrentPreviewItem()
        return true
    }

    func dismiss() {
        guard QLPreviewPanel.sharedPreviewPanelExists(),
              let panel = QLPreviewPanel.shared(),
              panel.dataSource === self else {
            return
        }
        panel.orderOut(nil)
        panel.dataSource = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewItem == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewItem
    }
}
