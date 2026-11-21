import SwiftUI
import UIKit
import VisionKit

/// Camera capture using the system camera UI. Unavailable in the simulator, so
/// callers must check `isCameraAvailable` and offer the photo library instead.
struct CameraPicker: UIViewControllerRepresentable {
    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = Self.isCameraAvailable ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let dismiss: DismissAction

        init(onCapture: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

/// Multi-page document scanning with VisionKit.
struct DocumentScannerView: UIViewControllerRepresentable {
    static var isSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }

    var onScan: ([UIImage]) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, dismiss: dismiss)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onScan: ([UIImage]) -> Void
        private let dismiss: DismissAction

        init(onScan: @escaping ([UIImage]) -> Void, dismiss: DismissAction) {
            self.onScan = onScan
            self.dismiss = dismiss
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var pages: [UIImage] = []
            for index in 0..<scan.pageCount {
                pages.append(scan.imageOfPage(at: index))
            }
            onScan(pages)
            dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            dismiss()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            dismiss()
        }
    }
}
