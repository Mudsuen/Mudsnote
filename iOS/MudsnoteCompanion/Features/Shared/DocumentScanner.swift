import SwiftUI
import UIKit
import VisionKit

@MainActor
enum CameraTextCapture {
    static let uiTestingArgument = "-ui-testing-scan-text"
    static let uiTestingText = "Scanned into Markdown"
    fileprivate static weak var currentFirstResponder: UIResponder?

    static var isAvailable: Bool {
        isUITesting || (DataScannerViewController.isSupported && DataScannerViewController.isAvailable)
    }

    @discardableResult
    static func start() -> Bool {
        if isUITesting {
            guard let input = firstResponder() as? UIKeyInput else { return false }
            input.insertText(uiTestingText)
            return true
        }
        return UIApplication.shared.sendAction(
            #selector(UIResponder.captureTextFromCamera(_:)),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingArgument)
    }

    private static func firstResponder() -> UIResponder? {
        currentFirstResponder = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.mudsnoteStoreFirstResponder(_:)),
            to: nil,
            from: nil,
            for: nil
        )
        return currentFirstResponder
    }
}

private extension UIResponder {
    @objc func mudsnoteStoreFirstResponder(_ sender: Any?) {
        CameraTextCapture.currentFirstResponder = self
    }
}

enum CameraPhotoCapture {
    enum Error: LocalizedError, Equatable {
        case invalidImage

        var errorDescription: String? {
            String(localized: "The photo could not be prepared.")
        }
    }

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    static func jpegData(for image: UIImage, compressionQuality: CGFloat = 0.9) throws -> Data {
        guard image.size.width > 0,
              image.size.height > 0,
              let data = image.jpegData(compressionQuality: compressionQuality),
              !data.isEmpty else {
            throw Error.invalidImage
        }
        return data
    }
}

struct CameraPhotoCaptureView: UIViewControllerRepresentable {
    let onComplete: (Result<Data, Swift.Error>) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.allowsEditing = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onComplete: (Result<Data, Swift.Error>) -> Void
        let onCancel: () -> Void

        init(
            onComplete: @escaping (Result<Data, Swift.Error>) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onComplete = onComplete
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                onComplete(.failure(CameraPhotoCapture.Error.invalidImage))
                return
            }
            do {
                onComplete(.success(try CameraPhotoCapture.jpegData(for: image)))
            } catch {
                onComplete(.failure(error))
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

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
