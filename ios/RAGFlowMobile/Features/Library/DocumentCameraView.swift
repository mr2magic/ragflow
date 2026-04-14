import SwiftUI
import VisionKit

/// Wraps VNDocumentCameraViewController so users can scan physical documents
/// with their camera and import them into a knowledge base.
///
/// The scanned pages are OCR'd by VisionOCRParser and saved as a plain-text
/// Book in the KB — no PDF layer needed.
struct DocumentCameraView: UIViewControllerRepresentable {
    let kbId: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(kbId: kbId, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let kbId: String
        private let dismiss: DismissAction

        init(kbId: String, dismiss: DismissAction) {
            self.kbId = kbId
            self.dismiss = dismiss
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let images: [UIImage] = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            dismiss()
            Task { await ingest(images: images) }
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

        // MARK: - OCR + ingest

        @MainActor
        private func ingest(images: [UIImage]) async {
            let parser = VisionOCRParser()
            var allText = ""
            for image in images {
                let pageText = await parser.extractText(from: image)
                if !pageText.isEmpty {
                    allText += pageText + "\n\n"
                }
            }
            guard !allText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            // Write the combined text to a temp file and ingest as plain text
            let filename = "Scan \(Date().formatted(date: .abbreviated, time: .shortened)).txt"
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("txt")
            guard (try? allText.write(to: tmpURL, atomically: true, encoding: .utf8)) != nil else { return }

            // Rename so the title is readable
            let namedURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try? FileManager.default.moveItem(at: tmpURL, to: namedURL)

            _ = try? await RAGService.shared.ingest(url: namedURL, kbId: kbId)
        }
    }
}

// MARK: - Availability Guard

/// Returns true when the device has a camera capable of document scanning.
var isDocumentScanningAvailable: Bool {
    VNDocumentCameraViewController.isSupported
}
