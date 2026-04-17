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

            // Write directly to a named file in a unique temp directory.
            // The previous two-step approach (write to a UUID file, then rename) failed
            // silently when the rename threw — leaving ingest() pointed at a nonexistent path.
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate]
            let dateStr = formatter.string(from: Date())
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let fileURL = tmpDir.appendingPathComponent("Scan \(dateStr).txt")
            do {
                try allText.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                return
            }

            if (try? await RAGService.shared.ingest(url: fileURL, kbId: kbId)) != nil {
                NotificationCenter.default.post(name: .scanImportComplete, object: kbId)
            }
        }
    }
}

// MARK: - Availability Guard

/// Returns true when the device has a camera capable of document scanning.
var isDocumentScanningAvailable: Bool {
    VNDocumentCameraViewController.isSupported
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted by DocumentCameraView after a scan is successfully ingested.
    /// `object` is the kbId (String) the scan was imported into.
    static let scanImportComplete = Notification.Name("com.dhorn.ragflowmobile.scanImportComplete")
}
