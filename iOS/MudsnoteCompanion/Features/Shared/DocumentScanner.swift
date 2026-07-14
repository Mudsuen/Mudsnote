import SwiftUI
import UIKit
import VisionKit

enum ScannedDocumentPDF {
    enum Error: LocalizedError, Equatable {
        case noPages
        case invalidPage

        var errorDescription: String? {
            switch self {
            case .noPages:
                String(localized: "No scanned pages were available.")
            case .invalidPage:
                String(localized: "A scanned page could not be prepared.")
            }
        }
    }

    static let suggestedFileName = "Scanned Document.pdf"

    static func data(for pages: [UIImage]) throws -> Data {
        guard !pages.isEmpty else { throw Error.noPages }
        guard pages.allSatisfy({ $0.size.width > 0 && $0.size.height > 0 }) else {
            throw Error.invalidPage
        }
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let contentBounds = pageBounds.insetBy(dx: 24, dy: 24)
        return UIGraphicsPDFRenderer(bounds: pageBounds).pdfData { context in
            for image in pages {
                context.beginPage()
                let size = image.size
                let scale = min(
                    contentBounds.width / size.width,
                    contentBounds.height / size.height
                )
                let renderedSize = CGSize(width: size.width * scale, height: size.height * scale)
                let rect = CGRect(
                    x: contentBounds.midX - renderedSize.width / 2,
                    y: contentBounds.midY - renderedSize.height / 2,
                    width: renderedSize.width,
                    height: renderedSize.height
                )
                image.draw(in: rect)
            }
        }
    }
}

struct DocumentScannerView: UIViewControllerRepresentable {
    let onComplete: (Result<[UIImage], Swift.Error>) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onComplete: (Result<[UIImage], Swift.Error>) -> Void
        let onCancel: () -> Void

        init(
            onComplete: @escaping (Result<[UIImage], Swift.Error>) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onComplete = onComplete
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            onComplete(.success((0..<scan.pageCount).map { scan.imageOfPage(at: $0) }))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Swift.Error
        ) {
            onComplete(.failure(error))
        }
    }
}
